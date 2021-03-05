# Homebrew (un)installer

## Install Homebrew (on macOS or Linux)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

More installation information and options: https://docs.brew.sh/Installation.

If running Linux or WSL, [there are some pre-requisite packages to install](https://docs.brew.sh/Homebrew-on-Linux#requirements).

You can set `HOMEBREW_BREW_GIT_REMOTE` and/or `HOMEBREW_CORE_GIT_REMOTE` in your shell environment to use custom Git mirrors to speed up brew update and brew tap.

```bash
export HOMEBREW_BREW_GIT_REMOTE="..."  # put your mirror URL of Homebrew/brew Git remote here
export HOMEBREW_CORE_GIT_REMOTE="..."  # put your mirror URL of Homebrew/core Git remote here
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

| Variable                 | Default                                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------------------ |
| HOMEBREW_BREW_GIT_REMOTE | macOS / Linux: https://github.com/Homebrew/brew                                                        |
| HOMEBREW_CORE_GIT_REMOTE | macOS: https://github.com/Homebrew/homebrew-core<br/>Linux: https://github.com/Homebrew/linuxbrew-core |

The default Git remote will be used if the corresponding environment variable is unset.

## Uninstall Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall.sh)"
```

Download the uninstall script and run `/bin/bash uninstall.sh --help` to view more uninstall options.
