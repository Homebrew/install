# Homebrew (un)installer

[![Build Status](https://travis-ci.org/Homebrew/install.svg?branch=master)](https://travis-ci.org/Homebrew/install)

## Install Homebrew
```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

More installation information and options at http://docs.brew.sh/Installation.html.

*Having trouble with the xcode command line tools?* Try this:

```bash
NO_CLI=true /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

## Uninstall Homebrew
```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
```

Download the uninstall script and run `./uninstall --help` to view more uninstall options.
