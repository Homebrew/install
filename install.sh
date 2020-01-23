#!/bin/bash
set -u

# This script installs to /usr/local only. To install elsewhere (which is
# unsupported) you can untar https://github.com/Homebrew/brew/tarball/master
# anywhere you like.
HOMEBREW_PREFIX="/usr/local"
HOMEBREW_REPOSITORY="/usr/local/Homebrew"
HOMEBREW_CACHE="${HOME}/Library/Caches/Homebrew"
BREW_REPO="https://github.com/Homebrew/brew"

# TODO: bump version when new macOS is released
MACOS_LATEST_SUPPORTED="10.15"
# TODO: bump version when new macOS is released
MACOS_OLDEST_SUPPORTED="10.13"

# no analytics during installation
export HOMEBREW_NO_ANALYTICS_THIS_RUN=1
export HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT=1

# string formatters
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"; do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}
chomp()
{
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

abort() {
  printf "%s\n" "$1"
  exit 1
}

execute() {
  if ! "$@"; then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

execute_sudo() {
  local -a args=("$@")
  if [[ -n "${SUDO_ASKPASS-}" ]]; then
    args=("-A" "${args[@]}")
  fi
  ohai "/usr/bin/sudo" "${args[@]}"
  execute "/usr/bin/sudo" "${args[@]}"
}

getc() {
  /bin/stty raw -echo
  IFS= read -r -n 1 -d '' "$@"
  /bin/stty -raw -echo
}

wait_for_user() {
  local c
  echo
  echo "Press RETURN to continue or any other key to abort"
  getc c
  # we test for \r and \n because some stuff does \r instead
  if ! [[ "$c" == $'\r' || "$c" == $'\n' ]]; then
    exit 1
  fi
}

# class Version
#   include Comparable
#   attr_reader :parts
#
#   def initialize(str)
#     @parts = str.split(".").map(&:to_i)
#   end
#
#   def <=>(other)
#     parts <=> self.class.new(other).parts
#   end
#
#   def to_s
#     parts.join(".")
#   end
# end

# def macos_version
#   @macos_version ||= Version.new(`/usr/bin/sw_vers -productVersion`.chomp[/10\.\d+/])
# end

should_install_command_line_tools() {
  if true; then # TODO: macos_version > "10.13"
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]]
  else
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]] ||
      ! [[ -e "/usr/include/iconv.h" ]]
  fi
}

get_permission() {
  stat -f "%A" "$1"
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 755 ]]
}

exists_but_not_writable() {
  [[ -e "$1" ]] && ! [[ -r "$1" && -w "$1" && -x "$1" ]]
}

get_owner() {
  stat -f "%u" "$1"
}

file_not_owned() {
  [[ "$(get_owner "$1")" != "$(id -u)" ]]
}

get_group() {
  stat -f "%g" "$1"
}

file_not_grpowned() {
  [[ " $(id -G "$USER") " != *" $(get_group "$1") "*  ]]
}

# USER isn't always set so provide a fall back for the installer and subprocesses.
if [[ -z "$USER" ]]; then
  export USER="$(chomp "$(id -un)")"
fi

# Invalidate sudo timestamp before exiting (if it wasn't active before).
/usr/bin/sudo -n -v 2>/dev/null
trap '/usr/bin/sudo -k' EXIT

# The block form of Dir.chdir fails later if Dir.CWD doesn't exist which I
# guess is fair enough. Also sudo prints a warning message for no good reason
cd "/usr"

####################################################################### script
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  abort "$(cat <<'EOABORT'
  To install Linuxbrew, paste at a terminal prompt:
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"
EOABORT
)"
elif false; then # TODO: macos_version < "10.7"
  abort "$(cat <<EOABORT
Your Mac OS X version is too old. See:
  ${tty_underline}https://github.com/mistydemeo/tigerbrew${tty_reset}
EOABORT
)"
elif false; then # TODO: macos_version < "10.9"
  abort "Your OS X version is too old"
elif [[ "$UID" == 0 ]]; then
  abort "Don't run this as root!"
elif ! [[ "$(dsmemberutil checkmembership -U "$USER" -G admin)" = *"user is a member"* ]]; then
  abort "This script requires the user $USER to be an Administrator."
elif [[ -d "$HOMEBREW_PREFIX" && ! -x "$HOMEBREW_PREFIX" ]]; then
  abort "$(cat <<EOABORT
The Homebrew prefix, ${HOMEBREW_PREFIX}, exists but is not searchable. If this is
not intentional, please restore the default permissions and try running the
installer again:
    sudo chmod 775 ${HOMEBREW_PREFIX}
EOABORT
)"
# TODO: bump version when new macOS is released
elif false; then # TODO: macos_version > MACOS_LATEST_SUPPORTED || macos_version < MACOS_OLDEST_SUPPORTED
  who="We"
  what=""
  if false; then # TODO: macos_version > MACOS_LATEST_SUPPORTED
    what="pre-release version"
  elif false; then # TODO: macos_version < MACOS_OLDEST_SUPPORTED
    who="$who (and Apple)"
    what="old version"
  else
    exit
  fi
  ohai "You are using macOS #{macos_version.parts.join(\".\")}." # TODO
  ohai "${who} do not provide support for this ${what}."

  echo "$(cat <<EOS
This installation may not succeed.
After installation, you will encounter build failures with some formulae.
Please create pull requests instead of asking for help on Homebrew\'s GitHub,
Discourse, Twitter or IRC. You are responsible for resolving any issues you
experience while you are running this ${what}.
EOS
)\n"
fi

ohai "This script will install:"
echo "${HOMEBREW_PREFIX}/bin/brew"
echo "${HOMEBREW_PREFIX}/share/doc/homebrew"
echo "${HOMEBREW_PREFIX}/share/man/man1/brew.1"
echo "${HOMEBREW_PREFIX}/share/zsh/site-functions/_brew"
echo "${HOMEBREW_PREFIX}/etc/bash_completion.d/brew"
echo "${HOMEBREW_REPOSITORY}"

# Keep relatively in sync with
# https://github.com/Homebrew/brew/blob/master/Library/Homebrew/keg.rb
declare -a directories=(bin etc include lib sbin share opt var
                        Frameworks
                        etc/bash_completion.d lib/pkgconfig
                        share/aclocal share/doc share/info share/locale share/man
                        share/man/man1 share/man/man2 share/man/man3 share/man/man4
                        share/man/man5 share/man/man6 share/man/man7 share/man/man8
                        var/log var/homebrew var/homebrew/linked
                        bin/brew)
declare -a group_chmods=()
for dir in "${directories[@]}"; do
  if exists_but_not_writable "${HOMEBREW_PREFIX}/${dir}"; then
    group_chmods+=("${HOMEBREW_PREFIX}/${dir}")
  fi
done

# zsh refuses to read from these directories if group writable
directories=(share/zsh share/zsh/site-functions)
declare -a zsh_dirs=()
for dir in "${directories[@]}"; do
  zsh_dirs+=("${HOMEBREW_PREFIX}/${dir}")
done

directories=(bin etc include lib sbin share var opt
             share/zsh share/zsh/site-functions
             var/homebrew var/homebrew/linked
             Cellar Caskroom Homebrew Frameworks)
declare -a mkdirs=()
for dir in "${directories[@]}"; do
  if ! [[ -d "${HOMEBREW_PREFIX}/${dir}" ]]; then
    mkdirs+=("${HOMEBREW_PREFIX}/${dir}")
  fi
done

declare -a user_chmods=()
if [[ "${#zsh_dirs[@]}" -ne 0 ]]; then
  for dir in "${zsh_dirs[@]-}"; do
    if user_only_chmod "${dir}"; then
      user_chmods+=("${dir}")
    fi
  done
fi

declare -a chmods=()
if [[ "${#group_chmods[@]}" -ne 0 ]]; then
  chmods+=("${group_chmods[@]-}")
fi
if [[ "${#user_chmods[@]}" -ne 0 ]]; then
  chmods+=("${user_chmods[@]-}")
fi

declare -a chowns=()
declare -a chgrps=()
if [[ "${#chmods[@]}" -ne 0 ]]; then
  for dir in "${chmods[@]-}"; do
    if file_not_owned "${dir}"; then
      chowns+=("${dir}")
    fi
    if file_not_grpowned "${dir}"; then
      chgrps+=("${dir}")
    fi
  done
fi

if [[ "${#group_chmods[@]}" -ne 0 ]]; then
  ohai "The following existing directories will be made group writable:"
  echo "${group_chmods[@]-}"
fi
if [[ "${#user_chmods[@]}" -ne 0 ]]; then
  ohai "The following existing directories will be made writable by user only:"
  echo "${user_chmods[@]-}"
fi
if [[ "${#chowns[@]}" -ne 0 ]]; then
  ohai "The following existing directories will have their owner set to ${tty_underline}${USER}${tty_reset}:"
  echo "${chowns[@]-}"
fi
if [[ "${#chgrps[@]}" -ne 0 ]]; then
  ohai "The following existing directories will have their group set to ${tty_underline}admin${tty_reset}:"
  echo "${chgrps[@]-}"
fi
if [[ "${#mkdirs[@]}" -ne 0 ]]; then
  ohai "The following new directories will be created:"
  echo "${mkdirs[@]-}"
fi

if should_install_command_line_tools; then
  ohai "The Xcode Command Line Tools will be installed."
fi

if [[ -t 0 && -z "${CI-}" ]]; then
  wait_for_user
fi

if [[ -d "${HOMEBREW_PREFIX}" ]]; then
  if [[ "${#chmods[@]}" -ne 0 ]]; then
    execute_sudo "/bin/chmod" "u+rwx" "${chmods[@]-}"
  fi
  if [[ "${#group_chmods[@]}" -ne 0 ]]; then
    execute_sudo "/bin/chmod" "g+rwx" "${group_chmods[@]-}"
  fi
  if [[ "${#user_chmods[@]}" -ne 0 ]]; then
    execute_sudo "/bin/chmod" "755" "${user_chmods[@]-}"
  fi
  if [[ "${#chowns[@]}" -ne 0 ]]; then
    execute_sudo "/usr/sbin/chown" "$USER" "${chowns[@]-}"
  fi
  if [[ "${#chgrps[@]}" -ne 0 ]]; then
    execute_sudo "/usr/bin/chgrp" "admin" "${chgrps[@]-}"
  fi
else
  execute_sudo "/bin/mkdir" "-p" "${HOMEBREW_PREFIX}"
  execute_sudo "/usr/sbin/chown" "root:wheel" "${HOMEBREW_PREFIX}"
fi

if [[ "${#mkdirs[@]}" -ne 0 ]]; then
  execute_sudo "/bin/mkdir" "-p" "${mkdirs[@]-}"
  execute_sudo "/bin/chmod" "g+rwx" "${mkdirs[@]-}"
  execute_sudo "/bin/chmod" "755" "${zsh_dirs[@]-}"
  execute_sudo "/usr/sbin/chown" "$USER" "${mkdirs[@]-}"
  execute_sudo "/usr/bin/chgrp" "admin" "${mkdirs[@]-}"
fi

if ! [[ -d "${HOMEBREW_CACHE}" ]]; then
  execute_sudo "/bin/mkdir" "-p" "${HOMEBREW_CACHE}"
fi
if exists_but_not_writable "${HOMEBREW_CACHE}"; then
  execute_sudo "/bin/chmod" "g+rwx" "${HOMEBREW_CACHE}"
fi
if file_not_owned "${HOMEBREW_CACHE}"; then
  execute_sudo "/usr/sbin/chown" "$USER" "${HOMEBREW_CACHE}"
fi
if file_not_grpowned "${HOMEBREW_CACHE}"; then
  execute_sudo "/usr/bin/chgrp" "admin" "${HOMEBREW_CACHE}"
fi
if [[ -d "${HOMEBREW_CACHE}" ]]; then
  execute "/usr/bin/touch" "${HOMEBREW_CACHE}/.cleaned"
fi

exit
if should_install_command_line_tools? && macos_version >= "10.13"
  ohai "Searching online for the Command Line Tools"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  clt_placeholder = "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo "/usr/bin/touch", clt_placeholder

  clt_label_command = "/usr/sbin/softwareupdate -l | " \
                      "grep -B 1 -E 'Command Line Tools' | " \
                      "awk -F'*' '/^ *\\*/ {print $2}' | " \
                      "sed -e 's/^ *Label: //' -e 's/^ *//' | " \
                      "sort -V | " \
                      "tail -n1"
  clt_label = `#{clt_label_command}`.chomp

  unless clt_label.empty?
    ohai "Installing #{clt_label}"
    sudo "/usr/sbin/softwareupdate", "-i", clt_label
    sudo "/bin/rm", "-f", clt_placeholder
    sudo "/usr/bin/xcode-select", "--switch", "/Library/Developer/CommandLineTools"
  end
end

# Headless install may have failed, so fallback to original 'xcode-select' method
if should_install_command_line_tools? && STDIN.tty?
  ohai "Installing the Command Line Tools (expect a GUI popup):"
  sudo "/usr/bin/xcode-select", "--install"
  puts "Press any key when the installation has completed."
  getc
  sudo "/usr/bin/xcode-select", "--switch", "/Library/Developer/CommandLineTools"
end

abort <<-EOABORT if `/usr/bin/xcrun clang 2>&1` =~ /license/ && !$CHILD_STATUS.success?
You have not agreed to the Xcode license.
Before running the installer again please agree to the license by opening
Xcode.app or running:
    sudo xcodebuild -license
EOABORT

ohai "Downloading and installing Homebrew..."
Dir.chdir HOMEBREW_REPOSITORY do
  # we do it in four steps to avoid merge errors when reinstalling
  system "git", "init", "-q"

  # "git remote add" will fail if the remote is defined in the global config
  system "git", "config", "remote.origin.url", BREW_REPO
  system "git", "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"

  # ensure we don't munge line endings on checkout
  system "git", "config", "core.autocrlf", "false"

  system "git", "fetch", "origin", "master:refs/remotes/origin/master",
         "--tags", "--force"

  system "git", "reset", "--hard", "origin/master"

  system "ln", "-sf", "#{HOMEBREW_REPOSITORY}/bin/brew", "#{HOMEBREW_PREFIX}/bin/brew"

  system "#{HOMEBREW_PREFIX}/bin/brew", "update", "--force"
end

warn "#{HOMEBREW_PREFIX}/bin is not in your PATH." unless ENV["PATH"].split(":").include? "#{HOMEBREW_PREFIX}/bin"

ohai "Installation successful!"
puts

# Use the shell's audible bell.
print "\a"

# Use an extra newline and bold to avoid this being missed.
ohai "Homebrew has enabled anonymous aggregate formulae and cask analytics."
puts <<-EOS
#{Tty.bold}Read the analytics documentation (and how to opt-out) here:
  #{Tty.underline}https://docs.brew.sh/Analytics#{Tty.reset}

EOS

ohai "Homebrew is run entirely by unpaid volunteers. Please consider donating:"
puts <<-EOS
  #{Tty.underline}https://github.com/Homebrew/brew#donations#{Tty.reset}
EOS

Dir.chdir HOMEBREW_REPOSITORY do
  system "git", "config", "--replace-all", "homebrew.analyticsmessage", "true"
  system "git", "config", "--replace-all", "homebrew.caskanalyticsmessage", "true"
end

ohai "Next steps:"
puts "- Run `brew help` to get started"
puts "- Further documentation: "
puts "    #{Tty.underline}https://docs.brew.sh#{Tty.reset}"
