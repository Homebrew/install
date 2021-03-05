# Homebrew (un)installer

## Install Homebrew (on macOS or Linux)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

More installation information and options: https://docs.brew.sh/Installation.

If running Linux or WSL, [there are some pre-requisite packages to install](https://docs.brew.sh/Homebrew-on-Linux#requirements).

You can set `HOMEBREW_BREW_GIT_REMOTE` and/or `HOMEBREW_CORE_GIT_REMOTE` in your shell environment to use geolocalized Git mirrors to speed up Homebrew's installation with this script and, after installation, `brew update`.

```bash
export HOMEBREW_BREW_GIT_REMOTE="..."  # put your Git mirror of Homebrew/brew here
export HOMEBREW_CORE_GIT_REMOTE="..."  # put your Git mirror of Homebrew/homebrew-core here
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

The default Git remote will be used if the corresponding environment variable is unset.

## Uninstall Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall.sh)"
```

Download the uninstall script and run `/bin/bash uninstall.sh --help` to view more uninstall options.
