# Homebrew (un)installer

## Install Homebrew

```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

More installation information and options at https://docs.brew.sh/Installation.html.

### Linux and Windows 10 Subsystem for Linux

Install Homebrew on Linux and Windows 10 Subsystem for Linux: https://docs.brew.sh/Linuxbrew.

## Uninstall Homebrew

```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
```

# On MacOS, Download the uninstall script by saving it as a raw file.
# Rename downloaded 'uninstall.txt' file and give ownership to it
`mv ~/Downloads/uninstall.txt ~/Downloads/uninstall && sudo chmod +x ~/Downloads/uninstall`
# CD to the directory of the file
`cd ~/Downloads/`
# run `./uninstall --help` to view more uninstall options.
`./uninstall --help`
