# Homebrew (un)installer

## Install Homebrew (on macOS or Linux)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

More installation information and options: <https://docs.brew.sh/Installation>.

For MDM deployments on Apple Silicon Macs, we recommend the `.pkg` installer from [Homebrew's latest GitHub release](https://github.com/Homebrew/brew/releases/latest).
Use [`HOMEBREW_PKG_USER`](https://docs.brew.sh/Installation) to select an existing non-root account to own the installation.
Installing without Git or developer tools requires a package release containing [Homebrew/brew#24062](https://github.com/Homebrew/brew/pull/24062).

If you are running Linux or WSL, [there are some pre-requisite packages to install](https://docs.brew.sh/Homebrew-on-Linux#requirements).

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

Use `--path` to choose an installation prefix. It must be an absolute path and, after resolving symlinks, no longer than the platform's default: `/opt/homebrew` on macOS or `/home/linuxbrew/.linuxbrew` on Linux. This allows bottles to be relocated into the chosen prefix.

For example, to install non-interactively into `/opt/brew`:

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" -- --path /opt/brew
```

The installing account does not need administrator membership when the prefix is writable.
On macOS, falling back to the `staff` group removes group and other write permissions from the prefix and cache.
Set `HOMEBREW_NO_SUDO=1` to prevent sudo calls; missing sudo, recognised privilege failures and explicit policy denials are also detected automatically.
Filesystem operations try without sudo before requesting elevation when needed.
Installations without sudo skip the system PATH file; follow the printed shell setup instructions instead.
Command Line Tools installation is skipped without sudo and CLT installation failures are non-fatal.
The shell installer aborts if Git is missing or unusable; a working Git on `PATH` or supplied by Xcode is supported.

## Uninstall Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

If you want to run the Homebrew uninstaller non-interactively, you can use:

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

If you want to to uninstall Homebrew from a specific prefix (e.g. when migrating from Intel to Apple Silicon processors), download the uninstall script and run it with `--path`:

```
curl -fsSLO https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh
/bin/bash uninstall.sh --path /usr/local
```

Run the downloaded script with `/bin/bash uninstall.sh --help` to view more uninstall options.
