#!/usr/bin/ruby
# This script installs to /usr/local only. To install elsewhere (which is
# unsupported) you can untar https://github.com/Homebrew/brew/tarball/master
# anywhere you like.
HOMEBREW_PREFIX = "/usr/local".freeze
HOMEBREW_REPOSITORY = "/usr/local/Homebrew".freeze
HOMEBREW_CACHE = "#{ENV["HOME"]}/Library/Caches/Homebrew".freeze
BREW_REPO = "https://github.com/Homebrew/brew".freeze

# TODO: bump version when new macOS is released
MACOS_LATEST_SUPPORTED = "10.15".freeze
# TODO: bump version when new macOS is released
MACOS_OLDEST_SUPPORTED = "10.13".freeze

# no analytics during installation
ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "1"
ENV["HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT"] = "1"

# get nicer global variables
require "English"

module Tty
  module_function

  def blue
    bold 34
  end

  def red
    bold 31
  end

  def reset
    escape 0
  end

  def bold(code = 39)
    escape "1;#{code}"
  end

  def underline
    escape "4;39"
  end

  def escape(code)
    "\033[#{code}m" if STDOUT.tty?
  end
end

class Array
  def shell_s
    cp = dup
    first = cp.shift
    cp.map { |arg| arg.gsub " ", "\\ " }.unshift(first).join(" ")
  end
end

def ohai(*args)
  puts "#{Tty.blue}==>#{Tty.bold} #{args.shell_s}#{Tty.reset}"
end

def warn(warning)
  puts "#{Tty.red}Warning#{Tty.reset}: #{warning.chomp}"
end

def system(*args)
  abort "Failed during: #{args.shell_s}" unless Kernel.system(*args)
end

def sudo(*args)
  args.unshift("-A") unless ENV["SUDO_ASKPASS"].nil?
  ohai "/usr/bin/sudo", *args
  system "/usr/bin/sudo", *args
end

def getc
  system "/bin/stty raw -echo"
  if STDIN.respond_to?(:getbyte)
    STDIN.getbyte
  else
    STDIN.getc
  end
ensure
  system "/bin/stty -raw echo"
end

def wait_for_user
  puts
  puts "Press RETURN to continue or any other key to abort"
  c = getc
  # we test for \r and \n because some stuff does \r instead
  abort unless (c == 13) || (c == 10)
end

class Version
  include Comparable
  attr_reader :parts

  def initialize(str)
    @parts = str.split(".").map(&:to_i)
  end

  def <=>(other)
    parts <=> self.class.new(other).parts
  end

  def to_s
    parts.join(".")
  end
end

def macos_version
  @macos_version ||= Version.new(`/usr/bin/sw_vers -productVersion`.chomp[/10\.\d+/])
end

def should_install_command_line_tools?
  if macos_version > "10.13"
    !File.exist?("/Library/Developer/CommandLineTools/usr/bin/git")
  else
    !File.exist?("/Library/Developer/CommandLineTools/usr/bin/git") ||
      !File.exist?("/usr/include/iconv.h")
  end
end

def user_only_chmod?(path)
  return false unless File.directory?(path)

  mode = File.stat(path).mode & 0777
  # u = (mode >> 6) & 07
  # g = (mode >> 3) & 07
  # o = (mode >> 0) & 07
  mode != 0755
end

def chmod?(path)
  File.exist?(path) && !(File.readable?(path) && File.writable?(path) && File.executable?(path))
end

def chown?(path)
  !File.owned?(path)
end

def chgrp?(path)
  !File.grpowned?(path)
end

# USER isn't always set so provide a fall back for the installer and subprocesses.
ENV["USER"] ||= `id -un`.chomp

# Invalidate sudo timestamp before exiting (if it wasn't active before).
Kernel.system "/usr/bin/sudo -n -v 2>/dev/null"
at_exit { Kernel.system "/usr/bin/sudo", "-k" } unless $CHILD_STATUS.success?

# The block form of Dir.chdir fails later if Dir.CWD doesn't exist which I
# guess is fair enough. Also sudo prints a warning message for no good reason
Dir.chdir "/usr"

####################################################################### script
if RUBY_PLATFORM.to_s.downcase.include?("linux")
  abort <<-EOABORT
  To install Linuxbrew, paste at a terminal prompt:
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"
  EOABORT
elsif macos_version < "10.7"
  abort <<-EOABORT
Your Mac OS X version is too old. See:
  #{Tty.underline}https://github.com/mistydemeo/tigerbrew#{Tty.reset}"
  EOABORT
elsif macos_version < "10.9"
  abort "Your OS X version is too old"
elsif Process.uid.zero?
  abort "Don't run this as root!"
elsif !`dsmemberutil checkmembership -U "#{ENV["USER"]}" -G admin`.include?("user is a member")
  abort "This script requires the user #{ENV["USER"]} to be an Administrator."
elsif File.directory?(HOMEBREW_PREFIX) && (!File.executable? HOMEBREW_PREFIX)
  abort <<-EOABORT
The Homebrew prefix, #{HOMEBREW_PREFIX}, exists but is not searchable. If this is
not intentional, please restore the default permissions and try running the
installer again:
    sudo chmod 775 #{HOMEBREW_PREFIX}
  EOABORT
# TODO: bump version when new macOS is released
elsif macos_version > MACOS_LATEST_SUPPORTED || macos_version < MACOS_OLDEST_SUPPORTED
  who = "We"
  if macos_version > MACOS_LATEST_SUPPORTED
    what = "pre-release version"
  elsif macos_version < MACOS_OLDEST_SUPPORTED
    who << " (and Apple)"
    what = "old version"
  else
    return
  end
  ohai "You are using macOS #{macos_version.parts.join(".")}."
  ohai "#{who} do not provide support for this #{what}."

  puts <<-EOS
This installation may not succeed.
After installation, you will encounter build failures with some formulae.
Please create pull requests instead of asking for help on Homebrew's GitHub,
Discourse, Twitter or IRC. You are responsible for resolving any issues you
experience while you are running this #{what}.

  EOS
end

ohai "This script will install:"
puts "#{HOMEBREW_PREFIX}/bin/brew"
puts "#{HOMEBREW_PREFIX}/share/doc/homebrew"
puts "#{HOMEBREW_PREFIX}/share/man/man1/brew.1"
puts "#{HOMEBREW_PREFIX}/share/zsh/site-functions/_brew"
puts "#{HOMEBREW_PREFIX}/etc/bash_completion.d/brew"
puts HOMEBREW_REPOSITORY.to_s

# Keep relatively in sync with
# https://github.com/Homebrew/brew/blob/master/Library/Homebrew/keg.rb
group_chmods = %w[bin etc include lib sbin share opt var
                  Frameworks
                  etc/bash_completion.d lib/pkgconfig
                  share/aclocal share/doc share/info share/locale share/man
                  share/man/man1 share/man/man2 share/man/man3 share/man/man4
                  share/man/man5 share/man/man6 share/man/man7 share/man/man8
                  var/log var/homebrew var/homebrew/linked
                  bin/brew]
               .map { |d| File.join(HOMEBREW_PREFIX, d) }
               .select { |d| chmod?(d) }
# zsh refuses to read from these directories if group writable
zsh_dirs = %w[share/zsh share/zsh/site-functions]
           .map { |d| File.join(HOMEBREW_PREFIX, d) }
mkdirs = %w[bin etc include lib sbin share var opt
            share/zsh share/zsh/site-functions
            var/homebrew var/homebrew/linked
            Cellar Caskroom Homebrew Frameworks]
         .map { |d| File.join(HOMEBREW_PREFIX, d) }
         .reject { |d| File.directory?(d) }

user_chmods = zsh_dirs.select { |d| user_only_chmod?(d) }
chmods = group_chmods + user_chmods
chowns = chmods.select { |d| chown?(d) }
chgrps = chmods.select { |d| chgrp?(d) }

unless group_chmods.empty?
  ohai "The following existing directories will be made group writable:"
  puts(*group_chmods)
end
unless user_chmods.empty?
  ohai "The following existing directories will be made writable by user only:"
  puts(*user_chmods)
end
unless chowns.empty?
  ohai "The following existing directories will have their owner set to #{Tty.underline}#{ENV["USER"]}#{Tty.reset}:"
  puts(*chowns)
end
unless chgrps.empty?
  ohai "The following existing directories will have their group set to #{Tty.underline}admin#{Tty.reset}:"
  puts(*chgrps)
end
unless mkdirs.empty?
  ohai "The following new directories will be created:"
  puts(*mkdirs)
end
if should_install_command_line_tools?
  ohai "The Xcode Command Line Tools will be installed."
end

wait_for_user if STDIN.tty? && !ENV["CI"]

if File.directory? HOMEBREW_PREFIX
  sudo "/bin/chmod", "u+rwx", *chmods unless chmods.empty?
  sudo "/bin/chmod", "g+rwx", *group_chmods unless group_chmods.empty?
  sudo "/bin/chmod", "755", *user_chmods unless user_chmods.empty?
  sudo "/usr/sbin/chown", ENV["USER"], *chowns unless chowns.empty?
  sudo "/usr/bin/chgrp", "admin", *chgrps unless chgrps.empty?
else
  sudo "/bin/mkdir", "-p", HOMEBREW_PREFIX
  sudo "/usr/sbin/chown", "root:wheel", HOMEBREW_PREFIX
end

unless mkdirs.empty?
  sudo "/bin/mkdir", "-p", *mkdirs
  sudo "/bin/chmod", "g+rwx", *mkdirs
  sudo "/bin/chmod", "755", *zsh_dirs
  sudo "/usr/sbin/chown", ENV["USER"], *mkdirs
  sudo "/usr/bin/chgrp", "admin", *mkdirs
end

sudo "/bin/mkdir", "-p", HOMEBREW_CACHE unless File.directory? HOMEBREW_CACHE
sudo "/bin/chmod", "g+rwx", HOMEBREW_CACHE if chmod? HOMEBREW_CACHE
sudo "/usr/sbin/chown", ENV["USER"], HOMEBREW_CACHE if chown? HOMEBREW_CACHE
sudo "/usr/bin/chgrp", "admin", HOMEBREW_CACHE if chgrp? HOMEBREW_CACHE
system "/usr/bin/touch", "#{HOMEBREW_CACHE}/.cleaned" if File.directory? HOMEBREW_CACHE

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
