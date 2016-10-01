#!/System/Library/Frameworks/Ruby.framework/Versions/Current/usr/bin/ruby

require "fileutils"
require "optparse"
require "pathname"

# Default options
options = {
  :force => false,
  :quiet => false,
  :dry_run => false,
  :skip_cache_and_logs => false,
}

# global status to indicate whether there is anything wrong.
$failed = false

module Tty extend self
  def blue; bold 34; end
  def white; bold 39; end
  def red; underline 31; end
  def reset; escape 0; end
  def bold n; escape "1;#{n}" end
  def underline n; escape "4;#{n}" end
  def escape n; "\033[#{n}m" if STDOUT.tty? end
end

class Array
  def shell_s
    cp = dup
    first = cp.shift
    cp.map{ |arg| arg.gsub " ", "\\ " }.unshift(first) * " "
  end
end

class Pathname
  def resolved_path
    self.symlink? ? dirname+readlink : self
  end

  def /(other)
    self + other.to_s
  end

  def pretty_print
    if self.symlink?
      puts to_s + " -> " + resolved_path.to_s
    elsif self.directory?
      puts to_s + "/"
    else
      puts to_s
    end
  end
end

def ohai *args
  puts "#{Tty.blue}==>#{Tty.white} #{args.shell_s}#{Tty.reset}"
end

def warn warning
  puts "#{Tty.red}Warning#{Tty.reset}: #{warning.chomp}"
end

def system *args
  unless Kernel.system(*args)
    warn "Failed during: #{args.shell_s}"
    $failed = true
  end
end

####################################################################### script

$HOMEBREW_PREFIX_CANDIDATES=[]

OptionParser.new do |opts|
  opts.banner = "Homebrew Uninstaller\nUsage: ./uninstall [options]"
  opts.summary_width = 16
  opts.on("-pPATH", "--path=PATH", "Sets Homebrew prefix. Defaults to /usr/local.") { |p| $HOMEBREW_PREFIX_CANDIDATES << Pathname.new(p) }
  opts.on("--skip-cache-and-logs", "Skips removal of HOMEBREW_CACHE and HOMEBREW_LOGS.") { |p| options[:skip_cache_and_logs] = true }
  opts.on("-f", "--force", "Uninstall without prompting.") { options[:force] = true }
  opts.on("-q", "--quiet", "Suppress all output.") { options[:quiet] = true }
  opts.on("-d", "--dry-run", "Simulate uninstall but don't remove anything.") { options[:dry_run] = true }
  opts.on_tail("-h", "--help", "Display this message.") { puts opts; exit }
end.parse!

if $HOMEBREW_PREFIX_CANDIDATES.empty? # Attempt to locate Homebrew unless `--path` is passed
  p = `brew --prefix` rescue ""
  $HOMEBREW_PREFIX_CANDIDATES << Pathname.new(p.strip) unless p.empty?
  p = `command -v brew` rescue `which brew` rescue ""
  $HOMEBREW_PREFIX_CANDIDATES << Pathname.new(p.strip).dirname.parent unless p.empty?
  $HOMEBREW_PREFIX_CANDIDATES << Pathname.new("/usr/local") # Homebrew default path
  $HOMEBREW_PREFIX_CANDIDATES << Pathname.new("#{ENV["HOME"]}/.linuxbrew") # Linuxbrew default path
end

HOMEBREW_PREFIX = $HOMEBREW_PREFIX_CANDIDATES.detect do |p|
  next unless p.directory?
  if p.to_s == "/usr/local" && File.exist?("/usr/local/Homebrew/.git")
    next true
  end
  (p/".git").exist? || (p/"bin/brew").executable?
end
abort "Failed to locate Homebrew!" if HOMEBREW_PREFIX.nil?

HOMEBREW_REPOSITORY = if (HOMEBREW_PREFIX/".git").exist?
  (HOMEBREW_PREFIX/".git").realpath.dirname
elsif (HOMEBREW_PREFIX/"bin/brew").exist?
  (HOMEBREW_PREFIX/"bin/brew").realpath.dirname.parent
end
abort "Failed to locate Homebrew!" if HOMEBREW_REPOSITORY.nil?

HOMEBREW_CELLAR = if (HOMEBREW_PREFIX/"Cellar").exist?
  HOMEBREW_PREFIX/"Cellar"
else
  HOMEBREW_REPOSITORY/"Cellar"
end

gitignore = begin
  (HOMEBREW_REPOSITORY/".gitignore").read
rescue Errno::ENOENT
  `curl -fsSL https://raw.githubusercontent.com/Homebrew/brew/master/.gitignore`
end
abort "Failed to fetch Homebrew .gitignore!" if gitignore.empty?

$HOMEBREW_FILES = gitignore.split("\n").select { |line| line.start_with? "!" }.
  map { |line| line.chomp("/").gsub(%r{^!?/}, "") }.
  reject { |line| %w[bin share share/doc].include?(line) }.
  map { |p| HOMEBREW_REPOSITORY/p }
if HOMEBREW_PREFIX.to_s != HOMEBREW_REPOSITORY.to_s
  $HOMEBREW_FILES << HOMEBREW_REPOSITORY
  $HOMEBREW_FILES += %w[
    bin/brew
    etc/bash_completion.d/brew
    share/doc/homebrew
    share/man/man1/brew.1
    share/man/man1/brew-cask.1
    share/zsh/site-functions/_brew
    share/zsh/site-functions/_brew_cask
    var/homebrew/locks/update
  ].map { |p| HOMEBREW_PREFIX/p }
else
  $HOMEBREW_FILES << HOMEBREW_REPOSITORY/".git"
end
$HOMEBREW_FILES << HOMEBREW_CELLAR

unless options[:skip_cache_and_logs]
  $HOMEBREW_FILES += %W[
    #{ENV["HOME"]}/Library/Caches/Homebrew
    #{ENV["HOME"]}/Library/Logs/Homebrew
    /Library/Caches/Homebrew
    #{ENV["HOME"]}/.cache/Homebrew
    #{ENV["HOMEBREW_CACHE"]}
    #{ENV["HOMEBREW_LOGS"]}
  ].map { |p| Pathname.new(p) }
end

if /darwin/i === RUBY_PLATFORM
  $HOMEBREW_FILES += %W[
    /Applications
    #{ENV["HOME"]}/Applications
  ].map { |p| Pathname.new(p) }.select(&:directory?).map do |p|
    p.children.select do |app|
      app.resolved_path.to_s.start_with? HOMEBREW_CELLAR.to_s
    end
  end.flatten
end

$HOMEBREW_FILES = $HOMEBREW_FILES.select(&:exist?).sort

unless options[:quiet]
  warn "This script #{options[:dry_run] ? "would" : "will"} remove:"
  $HOMEBREW_FILES.each(&:pretty_print)
end

if STDIN.tty? && (!options[:force] && !options[:dry_run])
  STDERR.print "Are you sure you want to uninstall Homebrew? [y/N] "
  abort unless gets.rstrip =~ /y|yes/i
end

ohai "Removing Homebrew installation..." unless options[:quiet]
paths = %W[Frameworks bin etc include lib opt sbin share var].
  map { |p| HOMEBREW_PREFIX/p }.select(&:exist?).map(&:to_s)
if paths.any?
  args = %W[-E] + paths + %W[-regex .*/info/([^.][^/]*\.info|dir)]
  if options[:dry_run]
    args << "-print"
  else
    args += %W[-exec /bin/bash -c]
    args << "/usr/bin/install-info --delete --quiet {} \"$(dirname {})/dir\""
    args << ";"
  end
  puts "Would delete:" if options[:dry_run]
  system "/usr/bin/find", *args
  args = paths + %W[-type l -lname */Cellar/*]
  if options[:dry_run]
    args << "-print"
  else
    args += %W[-exec unlink {} ;]
  end
  puts "Would delete:" if options[:dry_run]
  system "/usr/bin/find", *args
end

$HOMEBREW_FILES.each do |file|
  if options[:dry_run]
    puts "Would delete #{file}"
  else
    begin
      FileUtils.rm_rf(file)
    rescue => e
      warn "Failed to delete #{file}"
      puts e.message
      $failed = true
    end
  end
end

# Invalidate sudo timestamp before exiting
at_exit { Kernel.system "/usr/bin/sudo", "-k" }

def sudo *args
  ohai "/usr/bin/sudo", *args
  system "/usr/bin/sudo", *args
end

ohai "Removing empty directories..." unless options[:quiet]
paths = %W[Cellar Homebrew Frameworks bin etc include lib opt sbin share var].
  map { |p| HOMEBREW_PREFIX/p }.select(&:exist?).map(&:to_s)
if paths.any?
  args = paths + %W[-name .DS_Store]
  if options[:dry_run]
    args << "-print"
  else
    args << "-delete"
  end
  puts "Would delete:" if options[:dry_run]
  sudo "/usr/bin/find", *args
  args = paths + %W[-depth -type d -empty]
  if options[:dry_run]
    args << "-print"
  else
    args += %W[-exec rmdir {} ;]
  end
  puts "Would remove directories:" if options[:dry_run]
  sudo "/usr/bin/find", *args
end

if options[:dry_run]
  exit
else
  if HOMEBREW_PREFIX.to_s != "/usr/local" && HOMEBREW_PREFIX.exist?
    sudo "rmdir", "#{HOMEBREW_PREFIX}"
  end
  if HOMEBREW_PREFIX.to_s != HOMEBREW_REPOSITORY.to_s && HOMEBREW_REPOSITORY.exist?
    sudo "rmdir", "#{HOMEBREW_REPOSITORY}"
  end
end

unless options[:quiet]
  if $failed
    warn "Homebrew partially uninstalled (but there were steps that failed)!"
    puts "To finish uninstalling rerun this script with `sudo`."
  else
    ohai "Homebrew uninstalled!"
  end
end

residual_files = []
residual_files.concat(HOMEBREW_REPOSITORY.children) if HOMEBREW_REPOSITORY.exist?
residual_files.concat(HOMEBREW_PREFIX.children) if HOMEBREW_PREFIX.exist?
residual_files.uniq!

unless residual_files.empty? || options[:quiet]
  puts "The following possible Homebrew files were not deleted:"
  residual_files.each(&:pretty_print)
  puts "You may wish to remove them yourself.\n"
end

exit 1 if $failed
