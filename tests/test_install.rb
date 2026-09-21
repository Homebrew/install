# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class InstallPermissionsTest < Minitest::Test
  INSTALL = File.read(File.expand_path("../install.sh", __dir__))

  def setup
    @directory = Dir.mktmpdir
    @sudo = File.join(@directory, "sudo")
    @log = File.join(@directory, "sudo.log")
    File.write(@sudo, <<~'BASH')
      #!/bin/bash
      printf "%s\n" "$*" >> "$SUDO_TEST_LOG"
      printf "%s" "$SUDO_TEST_OUTPUT" >&2
      exit "${SUDO_TEST_STATUS:-1}"
    BASH
    File.chmod(0755, @sudo)
    @environment = {
      "HOMEBREW_NO_SUDO" => "",
      "HOMEBREW_ON_MACOS" => "1",
      "HOMEBREW_ON_LINUX" => "",
      "HAVE_SUDO_ACCESS" => nil,
      "NONINTERACTIVE" => "",
      "SUDO_ASKPASS" => "",
      "SUDO_TEST_OUTPUT" => "",
      "SUDO_TEST_STATUS" => "1",
      "USER" => "brewer",
      "SUDO_TEST_LOG" => @log,
    }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_fatal_sudo_errors_disable_elevation
    [
      'sudo: The "no new privileges" flag is set, which prevents sudo from running as root.',
      "sudo: effective uid is not 0, is sudo installed setuid root?",
      "sudo: /usr/bin/sudo must be owned by uid 0 and have the setuid bit set",
    ].each do |message|
      @environment["SUDO_TEST_OUTPUT"] = message
      stdout, = run_sudo_detection
      assert_equal "1\n", stdout, message
    end
  end

  def test_sudo_detection_preserves_credentials_and_inconclusive_failures
    [
      ["Sorry, user brewer may not run sudo on localhost.", "1", "1"],
      ["sudo: a password is required", "1", ""],
      ["sudo: unable to resolve host localhost", "1", ""],
      ["", "0", ""],
    ].each do |message, status, expected|
      @environment.merge!("SUDO_TEST_OUTPUT" => message, "SUDO_TEST_STATUS" => status)
      stdout, = run_sudo_detection
      assert_equal "#{expected}\n", stdout, message
    end
    assert_equal Array.new(4, "-n -k -l"), File.readlines(@log, chomp: true)
  end

  def test_explicit_no_sudo_does_not_probe
    @environment["HOMEBREW_NO_SUDO"] = "1"
    stdout, = run_sudo_detection
    assert_equal "1\n", stdout
    stdout, = run_shell('have_sudo_access; echo "status=$?"')
    assert_equal "status=1\n", stdout
    refute File.exist?(@log)
  end

  def test_non_admin_denial_does_not_abort
    stdout, stderr, = run_shell('have_sudo_access; echo "status=$?"')
    assert_equal "status=1\n", stdout
    assert_empty stderr
  end

  def test_sudo_notice_precedes_first_check_only
    @environment["SUDO_TEST_STATUS"] = "0"
    _, stderr, status = run_shell(<<~'BASH')
      ohai() { echo "$*" >> "$SUDO_TEST_LOG"; }
      have_sudo_access; have_sudo_access
    BASH
    assert_predicate status, :success?, stderr
    assert_equal ["Checking for `sudo` access (which may request your password)...", "-v", "-l mkdir"],
                 File.readlines(@log, chomp: true)
  end

  def test_system_path_entry_does_not_require_tee
    @environment["PATH"] = @directory
    @environment["SUDO_TEST_STATUS"] = "0"
    stdout, stderr, status = run_shell(
      "HOMEBREW_PREFIX=/opt/homebrew;\n" +
      INSTALL.split("# Create the system PATH entry", 2).last.split("HOMEBREW_CORE=", 2).first
             .split("\n", 2).last.gsub("/etc/paths.d", @directory) +
      'printf "%s\n" "${ADD_PATHS_D-}"',
    )
    assert_predicate status, :success?, stderr
    assert_equal "1\n", stdout
  end

  def test_noninteractive_sudo_notice_omits_password
    @environment["NONINTERACTIVE"] = "1"
    @environment["SUDO_TEST_STATUS"] = "0"
    stdout, stderr, status = run_shell('ohai() { echo "$*"; }; have_sudo_access')
    assert_predicate status, :success?, stderr
    assert_equal "Checking for `sudo` access...\n", stdout
    assert_equal ["-n -l mkdir"], File.readlines(@log, chomp: true)
  end

  def test_command_line_tools_require_sudo
    [
      ["", false, "1", "0", 1],
      ["", false, "", "1", 1],
      ["", false, "", "0", 0],
      ["", true, "1", "1", 1],
      ["1", false, "1", "1", 1],
    ].each do |linux, installed, no_sudo, sudo_status, expected_status|
      @environment.merge!("HOMEBREW_ON_LINUX" => linux, "HOMEBREW_NO_SUDO" => no_sudo,
                          "SUDO_TEST_STATUS" => sudo_status)
      stdout, = run_shell(
        shell_function("should_install_command_line_tools").gsub(
          "/Library/Developer/CommandLineTools/usr/bin/git",
          installed ? @sudo : File.join(@directory, "missing"),
        ) + 'should_install_command_line_tools; echo "status=$?"',
      )
      assert_equal "status=#{expected_status}\n", stdout, [linux, installed, no_sudo, sudo_status].inspect
    end
  end

  def test_command_line_tools_are_skipped_without_sudo
    @environment["HOMEBREW_NO_SUDO"] = "1"
    stdout, stderr, status = run_clt_installation(interactive: true)
    assert_predicate status, :success?, stderr
    assert_equal "Continuing installation\n", stdout
    refute File.exist?(File.join(@directory, "clt.log"))
    refute File.exist?(@log)
  end

  def test_headless_command_line_tools_failures_are_nonfatal
    ["touch", "softwareupdate -l", "softwareupdate -i", "xcode-select --switch", "rm"].each do |failure|
      stdout, stderr, status = run_clt_installation(failure: failure)
      assert_predicate status, :success?, "#{failure}: #{stderr}"
      assert_equal "Continuing installation\n", stdout, failure
      assert_includes File.read(File.join(@directory, "clt.log")), "rm -f", failure
    end
  end

  def test_interactive_command_line_tools_failures_are_nonfatal
    ["xcode-select --install", "xcode-select --switch"].each do |failure|
      stdout, stderr, status = run_clt_installation(failure: failure, interactive: true)
      assert_predicate status, :success?, "#{failure}: #{stderr}"
      assert_includes stdout, "Continuing installation\n", failure
      assert_includes File.read(File.join(@directory, "clt.log")), "xcode-select --install", failure
      refute_includes stdout, "Waiting for user", failure if failure == "xcode-select --install"
    end
  end

  def test_missing_or_unusable_git_is_fatal_on_macos
    [
      ["", 1, false],
      ["", 1, true],
      ["git version 2.54.0 (Apple Git-157)", 1, true],
      ["invalid version", 0, true],
      ["git version 2.6.0", 0, true],
    ].each do |output, exit_status, installed|
      stdout, stderr, status = run_git_detection(output: output, exit_status: exit_status, installed: installed)
      refute_predicate status, :success?, [output, exit_status, installed].inspect
      assert_includes stderr, "Git"
      refute_includes stdout, "Ready to download"
    end
  end

  def test_git_from_xcode_is_accepted
    stdout, stderr, status = run_git_detection(output: "git version 2.54.0 (Apple Git-157)")
    assert_predicate status, :success?, stderr
    assert_equal "Ready to download: #{@environment["GIT_TEST_PATH"]}\n", stdout
  end

  def test_git_from_path_is_accepted_without_developer_tools
    stdout, stderr, status = run_git_detection(output: "git version 2.54.0", developer_dir: "", git_on_path: true)
    assert_predicate status, :success?, stderr
    assert_equal "Ready to download: #{@environment["GIT_TEST_PATH"]}\n", stdout
    refute File.exist?(File.join(@directory, "apple-tools.log"))
  end

  def test_xcode_license_rejection_is_preserved
    @environment.merge!("GIT_TEST_CLANG_OUTPUT" => "You have not agreed to the Xcode license.",
                        "GIT_TEST_CLANG_STATUS" => "1")
    _, stderr, status = run_git_detection(output: "git version 2.54.0")
    refute_predicate status, :success?
    assert_includes stderr, "You have not agreed to the Xcode license."
  end

  def test_missing_developer_tools_do_not_invoke_apple_stubs
    ["", "/", File.join(@directory, "Missing Developer Tools")].each do |developer_dir|
      _, stderr, status = run_git_detection(output: "", installed: false, developer_dir: developer_dir)
      refute_predicate status, :success?, developer_dir
      assert_includes stderr, "Git"
      refute File.exist?(File.join(@directory, "apple-tools.log")), developer_dir
    end
  end

  def test_writable_operation_does_not_probe
    @environment["SUDO_TEST_STATUS"] = "0"
    _, stderr, status = run_shell("execute_sudo /usr/bin/true")
    assert_predicate status, :success?, stderr
    refute File.exist?(@log)
  end

  def test_failed_operation_retries_with_sudo
    @environment["SUDO_TEST_STATUS"] = "0"
    _, stderr, status = run_shell("execute_sudo /usr/bin/false")
    assert_predicate status, :success?, stderr
    assert_equal ["-v", "-l mkdir", "/usr/bin/false"], File.readlines(@log, chomp: true)
  end

  def test_non_admin_prefix_uses_own_group
    stdout, = run_shell(
      "id() { echo staff; };\n" +
      INSTALL.split("# Default installation paths.", 2).last.split('HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-', 2).first
             .gsub("/usr/bin/uname -m", "echo arm64") +
      "\nprintf \"%s\\n\" \"$GROUP|${INSTALL[*]}\"",
    )
    assert_equal "staff|/usr/bin/install -d -o brewer -g staff -m 0755\n", stdout
  end

  def test_staff_fallback_removes_group_and_other_write_permissions
    [false, true].each do |existing|
      prefix, cache, stdout, stderr, status = run_permission_setup(existing: existing)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      [prefix, cache].each do |root|
        [root, *Dir.glob("#{root}/**/*", File::FNM_DOTMATCH)].each do |path|
          next if [".", ".."].include?(File.basename(path))

          assert_equal 0, File.stat(path).mode & 0o022, path
          assert File.writable?(path), path
        end
      end
      refute File.exist?(@log)
    end
  end

  def test_other_groups_keep_group_write_permissions
    [
      ["1", "staff admin", "staff"],
      ["1", "brew-users", "brew-users"],
      ["", "staff", "staff"],
    ].each do |macos, groups, primary_group|
      prefix, _, stdout, stderr, status = run_permission_setup(macos: macos, groups: groups, primary_group: primary_group)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal 0o020, File.stat(File.join(prefix, "bin")).mode & 0o020
    end
  end

  private

  def run_permission_setup(existing: false, macos: "1", groups: "staff", primary_group: "staff")
    directory = Dir.mktmpdir("permissions", @directory)
    prefix = File.join(directory, "prefix")
    cache = File.join(directory, "cache")
    FileUtils.mkdir_p(prefix)
    if existing
      %w[prefix/bin prefix/.git cache].each do |path|
        FileUtils.mkdir_p(File.join(directory, path))
        File.chmod(0o777, File.join(directory, path))
      end
      %w[prefix/bin/brew prefix/.git/config cache/download].each do |path|
        File.write(File.join(directory, path), "existing file\n")
        File.chmod(0o666, File.join(directory, path))
      end
      File.chmod(0o777, prefix)
    end
    @environment.merge!("HOMEBREW_ON_MACOS" => macos, "HOMEBREW_NO_SUDO" => "1",
                        "PERMISSIONS_TEST_GROUPS" => groups, "PERMISSIONS_TEST_PRIMARY_GROUP" => primary_group)
    stdout, stderr, status = run_shell(
      <<~'BASH' +
        umask 000
        id() {
          if [[ "$1" == -Gn ]]; then echo "$PERMISSIONS_TEST_GROUPS"; else echo "$PERMISSIONS_TEST_PRIMARY_GROUP"; fi
        }
      BASH
      INSTALL.split("# Default installation paths.", 2).last.split('HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-', 2).first
             .gsub("/usr/bin/uname -m", "echo arm64") +
      %w[get_permission user_only_chmod exists_but_not_writable].map { |name| shell_function(name) }.join +
      <<~BASH +
        HOMEBREW_PREFIX="#{prefix}"
        HOMEBREW_REPOSITORY="#{prefix}"
        HOMEBREW_CACHE="#{cache}"
        CHMOD=(/bin/chmod)
        MKDIR=(/bin/mkdir -p)
        TOUCH=(/usr/bin/touch)
        CHOWN=(/usr/bin/true)
        CHGRP=(/usr/bin/true)
        STAT_PRINTF=(/usr/bin/stat #{RUBY_PLATFORM.include?("darwin") ? "-f" : "-c"})
        PERMISSION_FORMAT=#{RUBY_PLATFORM.include?("darwin") ? "%A" : "%a"}
        file_not_owned() { return 1; }
        file_not_grpowned() { return 1; }
      BASH
      INSTALL.split("# Keep relatively in sync with", 2).last.split("\nif should_install_command_line_tools", 2).first +
      "\nif [[ -d \"${HOMEBREW_PREFIX}\" ]]\n" +
      INSTALL.split("\nif [[ -d \"${HOMEBREW_PREFIX}\" ]]\n", 2).last.split("\nif should_install_command_line_tools", 2).first + <<~'BASH',
        mkdir "$HOMEBREW_PREFIX/new-directory"
        touch "$HOMEBREW_PREFIX/bin/new-file"
      BASH
    )
    [prefix, cache, stdout, stderr, status]
  end

  def run_sudo_detection
    detection = INSTALL.split("# Keep conservative detection", 2).last
                       .split("have_sudo_access()", 2).first.split("\n", 2).last
    run_shell(detection.gsub("/usr/bin/sudo", @sudo) + 'printf "%s\n" "$HOMEBREW_NO_SUDO"')
  end

  def shell_function(name)
    "#{name}() {#{INSTALL.split("#{name}() {", 2).last.split("\n}\n", 2).first}\n}\n"
  end

  def run_shell(script)
    helpers = %w[have_sudo_access execute execute_sudo should_install_command_line_tools chomp]
              .map { |name| shell_function(name) }.join.gsub("/usr/bin/sudo", @sudo)
    Open3.capture3(@environment, "/bin/bash", "-c",
                  "abort() { echo \"$*\" >&2; exit 1; }; ohai() { :; };\n#{helpers}#{script}")
  end

  def run_git_detection(output:, exit_status: 0, installed: true,
                        developer_dir: File.join(@directory, "Xcode Test.app"), git_on_path: false)
    @environment.merge!("HOMEBREW_NO_SUDO" => "1", "REQUIRED_GIT_VERSION" => "2.7.0",
                        "GIT_TEST_OUTPUT" => output, "GIT_TEST_STATUS" => exit_status.to_s,
                        "GIT_TEST_DEVELOPER_DIR" => developer_dir,
                        "GIT_TEST_LOG" => File.join(@directory, "apple-tools.log"),
                        "GIT_TEST_PATH" => File.join(@directory, git_on_path ? "bin/git" : "Xcode Test.app/usr/bin/git"),
                        "PATH" => "#{@directory}/bin:#{@directory}/system")
    FileUtils.rm_f(@environment["GIT_TEST_LOG"])
    if installed
      FileUtils.mkdir_p(File.dirname(@environment["GIT_TEST_PATH"]))
      File.write(@environment["GIT_TEST_PATH"], <<~'BASH')
        #!/bin/bash
        printf "%s\n" "$GIT_TEST_OUTPUT"
        exit "$GIT_TEST_STATUS"
      BASH
      File.chmod(0755, @environment["GIT_TEST_PATH"])
      unless git_on_path
        FileUtils.touch(File.join(@directory, "Xcode Test.app/usr/bin/clang"))
        File.chmod(0755, File.join(@directory, "Xcode Test.app/usr/bin/clang"))
      end
    end
    FileUtils.mkdir_p(File.join(@directory, "system"))
    FileUtils.ln_sf("/bin/cat", File.join(@directory, "system/cat"))
    File.write(File.join(@directory, "system/git"), "#!/bin/bash\necho git >> \"$GIT_TEST_LOG\"\nexit 1\n")
    File.write(File.join(@directory, "xcrun"), <<~'BASH')
      #!/bin/bash
      echo xcrun >> "$GIT_TEST_LOG"
      if [[ "$1" == clang ]]
      then
        printf '%s\n' "${GIT_TEST_CLANG_OUTPUT-}"
        exit "${GIT_TEST_CLANG_STATUS:-0}"
      fi
      printf '%s\n' "$GIT_TEST_PATH"
    BASH
    File.write(File.join(@directory, "xcode-select"), "#!/bin/bash\nprintf '%s\\n' \"$GIT_TEST_DEVELOPER_DIR\"\n")
    %w[system/git xcrun xcode-select].each { |tool| File.chmod(0755, File.join(@directory, tool)) }
    run_shell(
      (%w[major_minor version_ge test_git which find_tool].map { |name| shell_function(name) }.join +
       INSTALL.split("if should_install_command_line_tools && test -t 0", 2).last
         .split("\nfi\n", 2).last.split("\nif ! command -v curl", 2).first +
       "\necho \"Ready to download: ${USABLE_GIT}\"")
        .gsub('"/usr/bin/git"', "\"#{@directory}/system/git\"")
        .gsub("/usr/bin/xcrun", File.join(@directory, "xcrun"))
        .gsub("/usr/bin/xcode-select", File.join(@directory, "xcode-select")),
    )
  end

  def run_clt_installation(failure: "", interactive: false)
    @environment.merge!("SUDO_TEST_STATUS" => "0", "CLT_TEST_FAILURE" => failure,
                        "CLT_TEST_INTERACTIVE" => interactive ? "1" : "",
                        "CLT_TEST_LOG" => File.join(@directory, "clt.log"))
    FileUtils.rm_f(@environment["CLT_TEST_LOG"])
    File.write(File.join(@directory, "softwareupdate"), <<~'BASH')
      #!/bin/bash
      [[ "$CLT_TEST_FAILURE" != "softwareupdate -l" ]] || exit 1
      echo '* Label: Command Line Tools test'
    BASH
    File.chmod(0755, File.join(@directory, "softwareupdate"))
    run_shell(
      shell_function("should_install_command_line_tools").gsub(
        "/Library/Developer/CommandLineTools/usr/bin/git", File.join(@directory, "missing"),
      ) + <<~'BASH' +
        TOUCH=("/usr/bin/touch")
        warn() { echo "$*" >&2; }
        getc() { echo "Waiting for user"; }
        test() { [[ "$*" == "-t 0" && -n "$CLT_TEST_INTERACTIVE" ]]; }
        execute() {
          echo "${1##*/} ${*:2}" >> "$CLT_TEST_LOG"
          if [[ -n "$CLT_TEST_FAILURE" && "${1##*/} ${*:2}" == "$CLT_TEST_FAILURE"* ]]
          then
            abort "Simulated failure: $*"
          fi
        }
        execute_sudo() { execute "$@"; }
      BASH
      "if should_install_command_line_tools" + INSTALL.split("if should_install_command_line_tools", 3).last
        .split("\nxcode_path=", 2).first
        .gsub("/usr/sbin/softwareupdate", File.join(@directory, "softwareupdate")) +
      "\necho \"Continuing installation\"",
    )
  end
end
