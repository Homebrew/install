# Homebrew (un)installer

## Install Homebrew (on macOS or Linux)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

More installation information and options: <https://docs.brew.sh/Installation>.

If running Linux or WSL, [there are some pre-requisite packages to install](https://docs.brew.sh/Homebrew-on-Linux#requirements).

You can set `HOMEBREW_NO_INSTALL_FROM_API` to tap Homebrew/homebrew-core; by default, it will not be tapped as it is no longer necessary.

You can set `HOMEBREW_BREW_GIT_REMOTE` and/or `HOMEBREW_CORE_GIT_REMOTE` in your shell environment to use geolocalized Git mirrors to speed up Homebrew's installation with this script and, after installation, `brew update`.

```bash
export HOMEBREW_BREW_GIT_REMOTE="..."  # put your Git mirror of Homebrew/brew here
export HOMEBREW_CORE_GIT_REMOTE="..."  # put your Git mirror of Homebrew/homebrew-core here
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The default Git remote will be used if the corresponding environment variable is unset.

If you want to run the Homebrew installer non-interactively without prompting for passwords (e.g. in automation scripts), you can use:

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Uninstall Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

If you want to run the Homebrew uninstaller non-interactively, you can use:

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

Download the uninstall script and run `/bin/bash uninstall.sh --help` to view more uninstall options (copied below).

```
Homebrew Uninstaller
Usage: [NONINTERACTIVE=1] uninstall.sh [options]
    -p, --path=PATH  Sets Homebrew prefix. Defaults to /home/linuxbrew/.linuxbrew.
        --skip-cache-and-logs
                     Skips removal of HOMEBREW_CACHE and HOMEBREW_LOGS.
    -f, --force      Uninstall without prompting.
    -q, --quiet      Suppress all output.
    -n, --dry-run    Simulate uninstall but don't remove anything.
    -h, --help       Display this message.
    NONINTERACTIVE   Imply --force if NONINTERACTIVE is non-empty.
```
