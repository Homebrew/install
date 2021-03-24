#!/usr/bin/ruby

STDERR.print <<EOS
Warning: The Ruby Homebrew uninstaller is now deprecated and has been rewritten in
Bash. Please migrate to the following command:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

EOS

Kernel.exec "/bin/bash", "-c", '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"' + ' uninstall ' +  ARGV.join(" ")
