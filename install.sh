#!/bin/sh
set -eu
case "$(uname -s)" in
  Darwin) exec /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" "$@" ;;
  Linux)  exec /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)" "$@" ;;
  *) echo "Error: Your operating system is not supported: $(uname -s)" >&2; exit ;;
esac
