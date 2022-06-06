#!/bin/bash

# We don't need return codes for "$(command)", only stdout is needed.
# Allow `[[ -n "$(command)" ]]`, `func "$(command)"`, pipes, etc.
# shellcheck disable=SC2312

set -u

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]
then
  abort "Bash is required to interpret this script."
fi

# Check if script is run with force-interactive mode in CI
if [[ -n "${CI-}" && -n "${INTERACTIVE-}" ]]
then
  abort "Cannot run force-interactive mode in CI."
fi

# Check if both `INTERACTIVE` and `NONINTERACTIVE` are set
# Always use single-quoted strings with `exp` expressions
# shellcheck disable=SC2016
if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]
then
  abort 'Both `$INTERACTIVE` and `$NONINTERACTIVE` are set. Please unset at least one variable and try again.'
fi

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

# Check if script is run non-interactively (e.g. CI)
# If it is run non-interactively we should not prompt for passwords.
# Always use single-quoted strings with `exp` expressions
# shellcheck disable=SC2016
if [[ -z "${NONINTERACTIVE-}" ]]
then
  if [[ -n "${CI-}" ]]
  then
    warn 'Running in non-interactive mode because `$CI` is set.'
    NONINTERACTIVE=1
  elif [[ ! -t 0 ]]
  then
    if [[ -z "${INTERACTIVE-}" ]]
    then
      warn 'Running in non-interactive mode because `stdin` is not a TTY.'
      NONINTERACTIVE=1
    else
      warn 'Running in interactive mode despite `stdin` not being a TTY because `$INTERACTIVE` is set.'
    fi
  fi
else
  ohai 'Running in non-interactive mode because `$NONINTERACTIVE` is set.'
fi

# USER isn't always set so provide a fall back for the installer and subprocesses.
if [[ -z "${USER-}" ]]
then
  USER="$(chomp "$(id -un)")"
  export USER
fi

# First check OS.
OS="$(uname)"
if [[ "${OS}" == "Linux" ]]
then
  HOMEBREW_ON_LINUX=1
elif [[ "${OS}" != "Darwin" ]]
then
  abort "Homebrew is only supported on macOS and Linux."
fi

# Required installation paths. To install elsewhere (which is unsupported)
# you can untar https://github.com/Homebrew/brew/tarball/master
# anywhere you like.
if [[ -z "${HOMEBREW_ON_LINUX-}" ]]
then
  UNAME_MACHINE="$(/usr/bin/uname -m)"

  if [[ "${UNAME_MACHINE}" == "arm64" ]]
  then
    # On ARM macOS, this script installs to /opt/homebrew only
    HOMEBREW_PREFIX="/opt/homebrew"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}"
  else
    # On Intel macOS, this script installs to /usr/local only
    HOMEBREW_PREFIX="/usr/local"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
  fi
  HOMEBREW_CACHE="${HOME}/Library/Caches/Homebrew"

  STAT_PRINTF=("stat" "-f")
  PERMISSION_FORMAT="%A"
  CHOWN=("/usr/sbin/chown")
  CHGRP=("/usr/bin/chgrp")
  GROUP="admin"
  TOUCH=("/usr/bin/touch")
  INSTALL=("/usr/bin/install" -d -o "root" -g "wheel" -m "0755")
else
  UNAME_MACHINE="$(uname -m)"

  # On Linux, it installs to /home/linuxbrew/.linuxbrew if you have sudo access
  # and ~/.linuxbrew (which is unsupported) if run interactively.
  HOMEBREW_PREFIX_DEFAULT="/home/linuxbrew/.linuxbrew"
  HOMEBREW_CACHE="${HOME}/.cache/Homebrew"

  STAT_PRINTF=("stat" "--printf")
  PERMISSION_FORMAT="%a"
  CHOWN=("/bin/chown")
  CHGRP=("/bin/chgrp")
  GROUP="$(id -gn)"
  TOUCH=("/bin/touch")
  INSTALL=("/usr/bin/install" -d -o "${USER}" -g "${GROUP}" -m "0755")
fi
CHMOD=("/bin/chmod")
MKDIR=("/bin/mkdir" "-p")
HOMEBREW_BREW_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/brew"
HOMEBREW_CORE_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/homebrew-core"

# Use remote URLs of Homebrew repositories from environment if set.
HOMEBREW_BREW_GIT_REMOTE="${HOMEBREW_BREW_GIT_REMOTE:-"${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}"}"
HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_GIT_REMOTE:-"${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}"}"
# The URLs with and without the '.git' suffix are the same Git remote. Do not prompt.
if [[ "${HOMEBREW_BREW_GIT_REMOTE}" == "${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}.git" ]]
then
  HOMEBREW_BREW_GIT_REMOTE="${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}"
fi
if [[ "${HOMEBREW_CORE_GIT_REMOTE}" == "${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}.git" ]]
then
  HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}"
fi
export HOMEBREW_{BREW,CORE}_GIT_REMOTE

# TODO: bump version when new macOS is released or announced
MACOS_NEWEST_UNSUPPORTED="13.0"
# TODO: bump version when new macOS is released
MACOS_OLDEST_SUPPORTED="10.15"

# For Homebrew on Linux
REQUIRED_RUBY_VERSION=2.6    # https://github.com/Homebrew/brew/pull/6556
REQUIRED_GLIBC_VERSION=2.13  # https://docs.brew.sh/Homebrew-on-Linux#requirements
REQUIRED_CURL_VERSION=7.41.0 # HOMEBREW_MINIMUM_CURL_VERSION in brew.sh in Homebrew/brew
REQUIRED_GIT_VERSION=2.7.0   # HOMEBREW_MINIMUM_GIT_VERSION in brew.sh in Homebrew/brew

# no analytics during installation
export HOMEBREW_NO_ANALYTICS_THIS_RUN=1
export HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT=1

unset HAVE_SUDO_ACCESS # unset this from the environment

have_sudo_access() {
  if [[ ! -x "/usr/bin/sudo" ]]
  then
    return 1
  fi

  local -a SUDO=("/usr/bin/sudo")
  if [[ -n "${SUDO_ASKPASS-}" ]]
  then
    SUDO+=("-A")
  elif [[ -n "${NONINTERACTIVE-}" ]]
  then
    SUDO+=("-n")
  fi

  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]
  then
    if [[ -n "${NONINTERACTIVE-}" ]]
    then
      "${SUDO[@]}" -l mkdir &>/dev/null
    else
      "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
    fi
    HAVE_SUDO_ACCESS="$?"
  fi

  if [[ -z "${HOMEBREW_ON_LINUX-}" ]] && [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]]
  then
    abort "Need sudo access on macOS (e.g. the user ${USER} needs to be an Administrator)!"
  fi

  return "${HAVE_SUDO_ACCESS}"
}

execute() {
  if ! "$@"
  then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

execute_sudo() {
  local -a args=("$@")
  if have_sudo_access
  then
    if [[ -n "${SUDO_ASKPASS-}" ]]
    then
      args=("-A" "${args[@]}")
    fi
    ohai "/usr/bin/sudo" "${args[@]}"
    execute "/usr/bin/sudo" "${args[@]}"
  else
    ohai "${args[@]}"
    execute "${args[@]}"
  fi
}

getc() {
  local save_state
  save_state="$(/bin/stty -g)"
  /bin/stty raw -echo
  IFS='' read -r -n 1 -d '' "$@"
  /bin/stty "${save_state}"
}

ring_bell() {
  # Use the shell's audible bell.
  if [[ -t 1 ]]
  then
    printf "\a"
  fi
}

wait_for_user() {
  local c
  echo
  echo "Press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
  getc c
  # we test for \r and \n because some stuff does \r instead
  if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]
  then
    exit 1
  fi
}

major_minor() {
  echo "${1%%.*}.$(
    x="${1#*.}"
    echo "${x%%.*}"
  )"
}

version_gt() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -gt "${2#*.}" ]]
}
version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}
version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

should_install_command_line_tools() {
  if [[ -n "${HOMEBREW_ON_LINUX-}" ]]
  then
    return 1
  fi

  if version_gt "${macos_version}" "10.13"
  then
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]]
  else
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]] ||
      ! [[ -e "/usr/include/iconv.h" ]]
  fi
}

get_permission() {
  "${STAT_PRINTF[@]}" "${PERMISSION_FORMAT}" "$1"
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 75[0145] ]]
}

exists_but_not_writable() {
  [[ -e "$1" ]] && ! [[ -r "$1" && -w "$1" && -x "$1" ]]
}

get_owner() {
  "${STAT_PRINTF[@]}" "%u" "$1"
}

file_not_owned() {
  [[ "$(get_owner "$1")" != "$(id -u)" ]]
}

get_group() {
  "${STAT_PRINTF[@]}" "%g" "$1"
}

file_not_grpowned() {
  [[ " $(id -G "${USER}") " != *" $(get_group "$1") "* ]]
}

# Please sync with 'test_ruby()' in 'Library/Homebrew/utils/ruby.sh' from the Homebrew/brew repository.
test_ruby() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  "$1" --enable-frozen-string-literal --disable=gems,did_you_mean,rubyopt -rrubygems -e \
    "abort if Gem::Version.new(RUBY_VERSION.to_s.dup).to_s.split('.').first(2) != \
              Gem::Version.new('${REQUIRED_RUBY_VERSION}').to_s.split('.').first(2)" 2>/dev/null
}

test_curl() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  local curl_version_output curl_name_and_version
  curl_version_output="$("$1" --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  version_ge "$(major_minor "${curl_name_and_version##* }")" "$(major_minor "${REQUIRED_CURL_VERSION}")"
}

test_git() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  local git_version_output
  git_version_output="$("$1" --version 2>/dev/null)"
  version_ge "$(major_minor "${git_version_output##* }")" "$(major_minor "${REQUIRED_GIT_VERSION}")"
}

# Search for the given executable in PATH (avoids a dependency on the `which` command)
which() {
  # Alias to Bash built-in command `type -P`
  type -P "$@"
}

# Search PATH for the specified program that satisfies Homebrew requirements
# function which is set above
# shellcheck disable=SC2230
find_tool() {
  if [[ $# -ne 1 ]]
  then
    return 1
  fi

  local executable
  while read -r executable
  do
    if "test_$1" "${executable}"
    then
      echo "${executable}"
      break
    fi
  done < <(which -a "$1")
}

no_usable_ruby() {
  [[ -z "$(find_tool ruby)" ]]
}

outdated_glibc() {
  local glibc_version
  glibc_version="$(ldd --version | head -n1 | grep -o '[0-9.]*$' | grep -o '^[0-9]\+\.[0-9]\+')"
  version_lt "${glibc_version}" "${REQUIRED_GLIBC_VERSION}"
}

if [[ -n "${HOMEBREW_ON_LINUX-}" ]] && no_usable_ruby && outdated_glibc
then
  abort "$(
    cat <<EOABORT
Homebrew requires Ruby ${REQUIRED_RUBY_VERSION} which was not found on your system.
Homebrew portable Ruby requires Glibc version ${REQUIRED_GLIBC_VERSION} or newer,
and your Glibc version is too old. See:
  ${tty_underline}https://docs.brew.sh/Homebrew-on-Linux#requirements${tty_reset}
Please install Ruby ${REQUIRED_RUBY_VERSION} and add its location to your PATH.
EOABORT
  )"
fi

# Invalidate sudo timestamp before exiting (if it wasn't active before).
if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
then
  trap '/usr/bin/sudo -k' EXIT
fi

# Things can fail later if `pwd` doesn't exist.
# Also sudo prints a warning message for no good reason
cd "/usr" || exit 1

####################################################################### script
if ! command -v git >/dev/null
then
  abort "$(
    cat <<EOABORT
You must install Git before installing Homebrew. See:
  ${tty_underline}https://docs.brew.sh/Installation${tty_reset}
EOABORT
  )"
elif [[ -n "${HOMEBREW_ON_LINUX-}" ]]
then
  USABLE_GIT="$(find_tool git)"
  if [[ -z "${USABLE_GIT}" ]]
  then
    abort "$(
      cat <<EOABORT
The version of Git that was found does not satisfy requirements for Homebrew.
Please install Git ${REQUIRED_GIT_VERSION} or newer and add it to your PATH.
EOABORT
    )"
  elif [[ "${USABLE_GIT}" != /usr/bin/git ]]
  then
    export HOMEBREW_GIT_PATH="${USABLE_GIT}"
    ohai "Found Git: ${HOMEBREW_GIT_PATH}"
  fi
fi

if ! command -v curl >/dev/null
then
  abort "$(
    cat <<EOABORT
You must install cURL before installing Homebrew. See:
  ${tty_underline}https://docs.brew.sh/Installation${tty_reset}
EOABORT
  )"
elif [[ -n "${HOMEBREW_ON_LINUX-}" ]]
then
  USABLE_CURL="$(find_tool curl)"
  if [[ -z "${USABLE_CURL}" ]]
  then
    abort "$(
      cat <<EOABORT
The version of cURL that was found does not satisfy requirements for Homebrew.
Please install cURL ${REQUIRED_CURL_VERSION} or newer and add it to your PATH.
EOABORT
    )"
  elif [[ "${USABLE_CURL}" != /usr/bin/curl ]]
  then
    export HOMEBREW_CURL_PATH="${USABLE_CURL}"
    ohai "Found cURL: ${HOMEBREW_CURL_PATH}"
  fi
fi

# Set HOMEBREW_DEVELOPER on Linux systems where usable Git/cURL is not in /usr/bin
if [[ -n "${HOMEBREW_ON_LINUX-}" && (-n "${HOMEBREW_CURL_PATH-}" || -n "${HOMEBREW_GIT_PATH-}") ]]
then
  ohai "Setting HOMEBREW_DEVELOPER to use Git/cURL not in /usr/bin"
  export HOMEBREW_DEVELOPER=1
fi

# shellcheck disable=SC2016
ohai 'Checking for `sudo` access (which may request your password)...'

if [[ -z "${HOMEBREW_ON_LINUX-}" ]]
then
  have_sudo_access
else
  if [[ -w "${HOMEBREW_PREFIX_DEFAULT}" ]] ||
     [[ -w "/home/linuxbrew" ]] ||
     [[ -w "/home" ]]
  then
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX_DEFAULT}"
  elif [[ -n "${NONINTERACTIVE-}" ]]
  then
    if have_sudo_access
    then
      HOMEBREW_PREFIX="${HOMEBREW_PREFIX_DEFAULT}"
    else
      abort "Insufficient permissions to install Homebrew to \"${HOMEBREW_PREFIX_DEFAULT}\"."
    fi
  else
    trap exit SIGINT
    if ! /usr/bin/sudo -n -v &>/dev/null
    then
      ohai "Select a Homebrew installation directory:"
      echo "- ${tty_bold}Enter your password${tty_reset} to install to ${tty_underline}${HOMEBREW_PREFIX_DEFAULT}${tty_reset} (${tty_bold}recommended${tty_reset})"
      echo "- ${tty_bold}Press Control-D${tty_reset} to install to ${tty_underline}${HOME}/.linuxbrew${tty_reset}"
      echo "- ${tty_bold}Press Control-C${tty_reset} to cancel installation"
    fi
    if have_sudo_access
    then
      HOMEBREW_PREFIX="${HOMEBREW_PREFIX_DEFAULT}"
    else
      HOMEBREW_PREFIX="${HOME}/.linuxbrew"
    fi
    trap - SIGINT
  fi
  HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
fi
HOMEBREW_CORE="${HOMEBREW_REPOSITORY}/Library/Taps/homebrew/homebrew-core"

if [[ "${EUID:-${UID}}" == "0" ]]
then
  # Allow Azure Pipelines/GitHub Actions/Docker/Concourse/Kubernetes to do everything as root (as it's normal there)
  if ! [[ -f /proc/1/cgroup ]] ||
     ! grep -E "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup
  then
    abort "Don't run this as root!"
  fi
fi

if [[ -d "${HOMEBREW_PREFIX}" && ! -x "${HOMEBREW_PREFIX}" ]]
then
  abort "$(
    cat <<EOABORT
The Homebrew prefix ${tty_underline}${HOMEBREW_PREFIX}${tty_reset} exists but is not searchable.
If this is not intentional, please restore the default permissions and
try running the installer again:
    sudo chmod 775 ${HOMEBREW_PREFIX}
EOABORT
  )"
fi

if [[ -z "${HOMEBREW_ON_LINUX-}" ]]
then
  # On macOS, support 64-bit Intel and ARM
  if [[ "${UNAME_MACHINE}" != "arm64" ]] && [[ "${UNAME_MACHINE}" != "x86_64" ]]
  then
    abort "Homebrew is only supported on Intel and ARM processors!"
  fi
else
  # On Linux, support only 64-bit Intel
  if [[ "${UNAME_MACHINE}" == "aarch64" ]]
  then
    abort "$(
      cat <<EOABORT
Homebrew on Linux is not supported on ARM processors.
You can try an alternate installation method instead:
  ${tty_underline}https://docs.brew.sh/Homebrew-on-Linux#arm${tty_reset}
EOABORT
    )"
  elif [[ "${UNAME_MACHINE}" != "x86_64" ]]
  then
    abort "Homebrew on Linux is only supported on Intel processors!"
  fi
fi

if [[ -z "${HOMEBREW_ON_LINUX-}" ]]
then
  macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
  if version_lt "${macos_version}" "10.7"
  then
    abort "$(
      cat <<EOABORT
Your Mac OS X version is too old. See:
  ${tty_underline}https://github.com/mistydemeo/tigerbrew${tty_reset}
EOABORT
    )"
  elif version_lt "${macos_version}" "10.11"
  then
    abort "Your OS X version is too old."
  elif version_ge "${macos_version}" "${MACOS_NEWEST_UNSUPPORTED}" ||
       version_lt "${macos_version}" "${MACOS_OLDEST_SUPPORTED}"
  then
    who="We"
    what=""
    if version_ge "${macos_version}" "${MACOS_NEWEST_UNSUPPORTED}"
    then
      what="pre-release version"
    else
      who+=" (and Apple)"
      what="old version"
    fi
    ohai "You are using macOS ${macos_version}."
    ohai "${who} do not provide support for this ${what}."

    echo "$(
      cat <<EOS
This installation may not succeed.
After installation, you will encounter build failures with some formulae.
Please create pull requests instead of asking for help on Homebrew\'s GitHub,
Twitter or any other official channels. You are responsible for resolving any
issues you experience while you are running this ${what}.
EOS
    )
" | tr -d "\\"
  fi
fi

ohai "This script will install:"
echo "${HOMEBREW_PREFIX}/bin/brew"
echo "${HOMEBREW_PREFIX}/share/doc/homebrew"
echo "${HOMEBREW_PREFIX}/share/man/man1/brew.1"
echo "${HOMEBREW_PREFIX}/share/zsh/site-functions/_brew"
echo "${HOMEBREW_PREFIX}/etc/bash_completion.d/brew"
echo "${HOMEBREW_REPOSITORY}"

# Keep relatively in sync with
# https://github.com/Homebrew/brew/blob/master/Library/Homebrew/keg.rb
directories=(
  bin etc include lib sbin share opt var
  Frameworks
  etc/bash_completion.d lib/pkgconfig
  share/aclocal share/doc share/info share/locale share/man
  share/man/man1 share/man/man2 share/man/man3 share/man/man4
  share/man/man5 share/man/man6 share/man/man7 share/man/man8
  var/log var/homebrew var/homebrew/linked
  bin/brew
)
group_chmods=()
for dir in "${directories[@]}"
do
  if exists_but_not_writable "${HOMEBREW_PREFIX}/${dir}"
  then
    group_chmods+=("${HOMEBREW_PREFIX}/${dir}")
  fi
done

# zsh refuses to read from these directories if group writable
directories=(share/zsh share/zsh/site-functions)
zsh_dirs=()
for dir in "${directories[@]}"
do
  zsh_dirs+=("${HOMEBREW_PREFIX}/${dir}")
done

directories=(
  bin etc include lib sbin share var opt
  share/zsh share/zsh/site-functions
  var/homebrew var/homebrew/linked
  Cellar Caskroom Frameworks
)
mkdirs=()
for dir in "${directories[@]}"
do
  if ! [[ -d "${HOMEBREW_PREFIX}/${dir}" ]]
  then
    mkdirs+=("${HOMEBREW_PREFIX}/${dir}")
  fi
done

user_chmods=()
mkdirs_user_only=()
if [[ "${#zsh_dirs[@]}" -gt 0 ]]
then
  for dir in "${zsh_dirs[@]}"
  do
    if [[ ! -d "${dir}" ]]
    then
      mkdirs_user_only+=("${dir}")
    elif user_only_chmod "${dir}"
    then
      user_chmods+=("${dir}")
    fi
  done
fi

chmods=()
if [[ "${#group_chmods[@]}" -gt 0 ]]
then
  chmods+=("${group_chmods[@]}")
fi
if [[ "${#user_chmods[@]}" -gt 0 ]]
then
  chmods+=("${user_chmods[@]}")
fi

chowns=()
chgrps=()
if [[ "${#chmods[@]}" -gt 0 ]]
then
  for dir in "${chmods[@]}"
  do
    if file_not_owned "${dir}"
    then
      chowns+=("${dir}")
    fi
    if file_not_grpowned "${dir}"
    then
      chgrps+=("${dir}")
    fi
  done
fi

if [[ "${#group_chmods[@]}" -gt 0 ]]
then
  ohai "The following existing directories will be made group writable:"
  printf "%s\n" "${group_chmods[@]}"
fi
if [[ "${#user_chmods[@]}" -gt 0 ]]
then
  ohai "The following existing directories will be made writable by user only:"
  printf "%s\n" "${user_chmods[@]}"
fi
if [[ "${#chowns[@]}" -gt 0 ]]
then
  ohai "The following existing directories will have their owner set to ${tty_underline}${USER}${tty_reset}:"
  printf "%s\n" "${chowns[@]}"
fi
if [[ "${#chgrps[@]}" -gt 0 ]]
then
  ohai "The following existing directories will have their group set to ${tty_underline}${GROUP}${tty_reset}:"
  printf "%s\n" "${chgrps[@]}"
fi
if [[ "${#mkdirs[@]}" -gt 0 ]]
then
  ohai "The following new directories will be created:"
  printf "%s\n" "${mkdirs[@]}"
fi

if should_install_command_line_tools
then
  ohai "The Xcode Command Line Tools will be installed."
fi

non_default_repos=""
additional_shellenv_commands=()
if [[ "${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_BREW_GIT_REMOTE}" ]]
then
  ohai "HOMEBREW_BREW_GIT_REMOTE is set to a non-default URL:"
  echo "${tty_underline}${HOMEBREW_BREW_GIT_REMOTE}${tty_reset} will be used as the Homebrew/brew Git remote."
  non_default_repos="Homebrew/brew"
  additional_shellenv_commands+=("export HOMEBREW_BREW_GIT_REMOTE=\"${HOMEBREW_BREW_GIT_REMOTE}\"")
fi

if [[ "${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_CORE_GIT_REMOTE}" ]]
then
  ohai "HOMEBREW_CORE_GIT_REMOTE is set to a non-default URL:"
  echo "${tty_underline}${HOMEBREW_CORE_GIT_REMOTE}${tty_reset} will be used as the Homebrew/homebrew-core Git remote."
  non_default_repos="${non_default_repos:-}${non_default_repos:+ and }Homebrew/homebrew-core"
  additional_shellenv_commands+=("export HOMEBREW_CORE_GIT_REMOTE=\"${HOMEBREW_CORE_GIT_REMOTE}\"")
fi

if [[ -n "${HOMEBREW_INSTALL_FROM_API-}" ]]
then
  ohai "HOMEBREW_INSTALL_FROM_API is set."
  echo "Homebrew/homebrew-core will not be tapped during this ${tty_bold}install${tty_reset} run."
fi

if [[ -z "${NONINTERACTIVE-}" ]]
then
  ring_bell
  wait_for_user
fi

if [[ -d "${HOMEBREW_PREFIX}" ]]
then
  if [[ "${#chmods[@]}" -gt 0 ]]
  then
    execute_sudo "${CHMOD[@]}" "u+rwx" "${chmods[@]}"
  fi
  if [[ "${#group_chmods[@]}" -gt 0 ]]
  then
    execute_sudo "${CHMOD[@]}" "g+rwx" "${group_chmods[@]}"
  fi
  if [[ "${#user_chmods[@]}" -gt 0 ]]
  then
    execute_sudo "${CHMOD[@]}" "go-w" "${user_chmods[@]}"
  fi
  if [[ "${#chowns[@]}" -gt 0 ]]
  then
    execute_sudo "${CHOWN[@]}" "${USER}" "${chowns[@]}"
  fi
  if [[ "${#chgrps[@]}" -gt 0 ]]
  then
    execute_sudo "${CHGRP[@]}" "${GROUP}" "${chgrps[@]}"
  fi
else
  execute_sudo "${INSTALL[@]}" "${HOMEBREW_PREFIX}"
fi

if [[ "${#mkdirs[@]}" -gt 0 ]]
then
  execute_sudo "${MKDIR[@]}" "${mkdirs[@]}"
  execute_sudo "${CHMOD[@]}" "ug=rwx" "${mkdirs[@]}"
  if [[ "${#mkdirs_user_only[@]}" -gt 0 ]]
  then
    execute_sudo "${CHMOD[@]}" "go-w" "${mkdirs_user_only[@]}"
  fi
  execute_sudo "${CHOWN[@]}" "${USER}" "${mkdirs[@]}"
  execute_sudo "${CHGRP[@]}" "${GROUP}" "${mkdirs[@]}"
fi

if ! [[ -d "${HOMEBREW_REPOSITORY}" ]]
then
  execute_sudo "${MKDIR[@]}" "${HOMEBREW_REPOSITORY}"
fi
execute_sudo "${CHOWN[@]}" "-R" "${USER}:${GROUP}" "${HOMEBREW_REPOSITORY}"

if ! [[ -d "${HOMEBREW_CACHE}" ]]
then
  if [[ -z "${HOMEBREW_ON_LINUX-}" ]]
  then
    execute_sudo "${MKDIR[@]}" "${HOMEBREW_CACHE}"
  else
    execute "${MKDIR[@]}" "${HOMEBREW_CACHE}"
  fi
fi
if exists_but_not_writable "${HOMEBREW_CACHE}"
then
  execute_sudo "${CHMOD[@]}" "g+rwx" "${HOMEBREW_CACHE}"
fi
if file_not_owned "${HOMEBREW_CACHE}"
then
  execute_sudo "${CHOWN[@]}" "-R" "${USER}" "${HOMEBREW_CACHE}"
fi
if file_not_grpowned "${HOMEBREW_CACHE}"
then
  execute_sudo "${CHGRP[@]}" "-R" "${GROUP}" "${HOMEBREW_CACHE}"
fi
if [[ -d "${HOMEBREW_CACHE}" ]]
then
  execute "${TOUCH[@]}" "${HOMEBREW_CACHE}/.cleaned"
fi

if should_install_command_line_tools && version_ge "${macos_version}" "10.13"
then
  ohai "Searching online for the Command Line Tools"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  execute_sudo "${TOUCH[@]}" "${clt_placeholder}"

  clt_label_command="/usr/sbin/softwareupdate -l |
                      grep -B 1 -E 'Command Line Tools' |
                      awk -F'*' '/^ *\\*/ {print \$2}' |
                      sed -e 's/^ *Label: //' -e 's/^ *//' |
                      sort -V |
                      tail -n1"
  clt_label="$(chomp "$(/bin/bash -c "${clt_label_command}")")"

  if [[ -n "${clt_label}" ]]
  then
    ohai "Installing ${clt_label}"
    execute_sudo "/usr/sbin/softwareupdate" "-i" "${clt_label}"
    execute_sudo "/usr/bin/xcode-select" "--switch" "/Library/Developer/CommandLineTools"
  fi
  execute_sudo "/bin/rm" "-f" "${clt_placeholder}"
fi

# Headless install may have failed, so fallback to original 'xcode-select' method
if should_install_command_line_tools && test -t 0
then
  ohai "Installing the Command Line Tools (expect a GUI popup):"
  execute_sudo "/usr/bin/xcode-select" "--install"
  echo "Press any key when the installation has completed."
  getc
  execute_sudo "/usr/bin/xcode-select" "--switch" "/Library/Developer/CommandLineTools"
fi

if [[ -z "${HOMEBREW_ON_LINUX-}" ]] && ! output="$(/usr/bin/xcrun clang 2>&1)" && [[ "${output}" == *"license"* ]]
then
  abort "$(
    cat <<EOABORT
You have not agreed to the Xcode license.
Before running the installer again please agree to the license by opening
Xcode.app or running:
    sudo xcodebuild -license
EOABORT
  )"
fi

ohai "Downloading and installing Homebrew..."
(
  cd "${HOMEBREW_REPOSITORY}" >/dev/null || return

  # we do it in four steps to avoid merge errors when reinstalling
  execute "git" "init" "-q"

  # "git remote add" will fail if the remote is defined in the global config
  execute "git" "config" "remote.origin.url" "${HOMEBREW_BREW_GIT_REMOTE}"
  execute "git" "config" "remote.origin.fetch" "+refs/heads/*:refs/remotes/origin/*"

  # ensure we don't munge line endings on checkout
  execute "git" "config" "core.autocrlf" "false"

  execute "git" "fetch" "--force" "origin"
  execute "git" "fetch" "--force" "--tags" "origin"

  execute "git" "reset" "--hard" "origin/master"

  if [[ "${HOMEBREW_REPOSITORY}" != "${HOMEBREW_PREFIX}" ]]
  then
    if [[ "${HOMEBREW_REPOSITORY}" == "${HOMEBREW_PREFIX}/Homebrew" ]]
    then
      execute "ln" "-sf" "../Homebrew/bin/brew" "${HOMEBREW_PREFIX}/bin/brew"
    else
      abort "The Homebrew/brew repository should be placed in the Homebrew prefix directory."
    fi
  fi

  if [[ -n "${HOMEBREW_INSTALL_FROM_API-}" ]]
  then
    # shellcheck disable=SC2016
    ohai 'Skip tapping homebrew/core because `$HOMEBREW_INSTALL_FROM_API` is set.'
    # Unset HOMEBREW_DEVELOPER since it is no longer needed and causes warnings during brew update below
    if [[ -n "${HOMEBREW_ON_LINUX-}" && (-n "${HOMEBREW_CURL_PATH-}" || -n "${HOMEBREW_GIT_PATH-}") ]]
    then
      export -n HOMEBREW_DEVELOPER
    fi
  elif [[ ! -d "${HOMEBREW_CORE}" ]]
  then
    ohai "Tapping homebrew/core"
    (
      execute "${MKDIR[@]}" "${HOMEBREW_CORE}"
      cd "${HOMEBREW_CORE}" >/dev/null || return

      execute "git" "init" "-q"
      execute "git" "config" "remote.origin.url" "${HOMEBREW_CORE_GIT_REMOTE}"
      execute "git" "config" "remote.origin.fetch" "+refs/heads/*:refs/remotes/origin/*"
      execute "git" "config" "core.autocrlf" "false"
      execute "git" "fetch" "--force" "origin" "refs/heads/master:refs/remotes/origin/master"
      execute "git" "remote" "set-head" "origin" "--auto" >/dev/null
      execute "git" "reset" "--hard" "origin/master"

      cd "${HOMEBREW_REPOSITORY}" >/dev/null || return
    ) || exit 1
  fi

  execute "${HOMEBREW_PREFIX}/bin/brew" "update" "--force" "--quiet"
) || exit 1

if [[ ":${PATH}:" != *":${HOMEBREW_PREFIX}/bin:"* ]]
then
  warn "${HOMEBREW_PREFIX}/bin is not in your PATH.
  Instructions on how to configure your shell for Homebrew
  can be found in the 'Next steps' section below."
fi

ohai "Installation successful!"
echo

ring_bell

# Use an extra newline and bold to avoid this being missed.
ohai "Homebrew has enabled anonymous aggregate formulae and cask analytics."
echo "$(
  cat <<EOS
${tty_bold}Read the analytics documentation (and how to opt-out) here:
  ${tty_underline}https://docs.brew.sh/Analytics${tty_reset}
No analytics data has been sent yet (nor will any be during this ${tty_bold}install${tty_reset} run).
EOS
)
"

ohai "Homebrew is run entirely by unpaid volunteers. Please consider donating:"
echo "$(
  cat <<EOS
  ${tty_underline}https://github.com/Homebrew/brew#donations${tty_reset}
EOS
)
"

(
  cd "${HOMEBREW_REPOSITORY}" >/dev/null || return
  execute "git" "config" "--replace-all" "homebrew.analyticsmessage" "true"
  execute "git" "config" "--replace-all" "homebrew.caskanalyticsmessage" "true"
) || exit 1

ohai "Next steps:"
case "${SHELL}" in
  */bash*)
    if [[ -r "${HOME}/.bash_profile" ]]
    then
      shell_profile="${HOME}/.bash_profile"
    else
      shell_profile="${HOME}/.profile"
    fi
    ;;
  */zsh*)
    shell_profile="${HOME}/.zprofile"
    ;;
  *)
    shell_profile="${HOME}/.profile"
    ;;
esac

# `which` is a shell function defined above.
# shellcheck disable=SC2230
if [[ "$(which brew)" != "${HOMEBREW_PREFIX}/bin/brew" ]]
then
  cat <<EOS
- Run these two commands in your terminal to add Homebrew to your ${tty_bold}PATH${tty_reset}:
    echo 'eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"' >> ${shell_profile}
    eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
EOS
fi
if [[ -n "${non_default_repos}" ]]
then
  plural=""
  if [[ "${#additional_shellenv_commands[@]}" -gt 1 ]]
  then
    plural="s"
  fi
  echo "- Run these commands in your terminal to add the non-default Git remote${plural} for ${non_default_repos}:"
  printf "    echo '%s' >> ${shell_profile}\n" "${additional_shellenv_commands[@]}"
  printf "    %s\n" "${additional_shellenv_commands[@]}"
fi

if [[ -n "${HOMEBREW_ON_LINUX-}" ]]
then
  echo "- Install Homebrew's dependencies if you have sudo access:"

  if [[ -x "$(command -v apt-get)" ]]
  then
    echo "    sudo apt-get install build-essential"
  elif [[ -x "$(command -v yum)" ]]
  then
    echo "    sudo yum groupinstall 'Development Tools'"
  elif [[ -x "$(command -v pacman)" ]]
  then
    echo "    sudo pacman -S base-devel"
  elif [[ -x "$(command -v apk)" ]]
  then
    echo "    sudo apk add build-base"
  fi

  cat <<EOS
  For more information, see:
    ${tty_underline}https://docs.brew.sh/Homebrew-on-Linux${tty_reset}
- We recommend that you install GCC:
    brew install gcc
EOS
fi

cat <<EOS
- Run ${tty_bold}brew help${tty_reset} to get started
- Further documentation:
    ${tty_underline}https://docs.brew.sh${tty_reset}

EOS
