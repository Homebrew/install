#!/bin/bash
set -u
shopt -s extglob

abort() {
  printf "%s\n" "$@"
  exit 1
}

strip_s() {
  local s
  for s in "$@"
  do
    s="${s## }"
    echo "${s%% }"
  done
}

dir_children() {
  local p
  for p in "$@"
  do
    [[ -d "${p}" ]] || continue
    find "${p}" -mindepth 1 -maxdepth 1
  done
}

# Set up temp dir
tmpdir="/tmp/uninstall.$$"
mkdir -p "${tmpdir}" || abort "Unable to create temp dir '${tmpdir}'"
trap '
  rm -fr "${tmpdir}"
  # Invalidate sudo timestamp before exiting
  /usr/bin/sudo -k
' EXIT

# Default options
opt_force=""
opt_quiet=""
opt_dry_run=""
opt_skip_cache_and_logs=""

# global status to indicate whether there is anything wrong.
failed=false

un="$(uname)"
case "${un}" in
  Linux)
    ostype=linux
    homebrew_prefix_default=/home/linuxbrew/.linuxbrew
    ;;
  Darwin)
    ostype=macos
    if [[ "$(uname -m)" == "arm64" ]]
    then
      homebrew_prefix_default=/opt/homebrew
    else
      homebrew_prefix_default=/usr/local
    fi
    realpath() {
      cd "$(dirname "$1")" && echo "$(pwd -P)/$(basename "$1")"
    }
    ;;
  *)
    abort "Unsupported system type '${un}'"
    ;;
esac

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;${1:-39}"; }
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

have_sudo_access() {
  local -a args
  if [[ -n "${SUDO_ASKPASS-}" ]]
  then
    args=("-A")
  fi

  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]
  then
    if [[ -n "${args[*]-}" ]]
    then
      /usr/bin/sudo "${args[@]}" -l mkdir &>/dev/null
    else
      /usr/bin/sudo -l mkdir &>/dev/null
    fi
    HAVE_SUDO_ACCESS="$?"
  fi

  if [[ -z "${HOMEBREW_ON_LINUX-}" ]] && [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]]
  then
    abort "Need sudo access on macOS (e.g. the user ${USER} to be an Administrator)!"
  fi

  return "${HAVE_SUDO_ACCESS}"
}

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

resolved_pathname() { realpath "$1"; }

pretty_print_pathnames() {
  local p
  for p in "$@"
  do
    if [[ -L "${p}" ]]
    then
      printf '%s -> %s\n' "${p}" "$(resolved_pathname "${p}")"
    elif [[ -d "${p}" ]]
    then
      echo "${p}/"
    else
      echo "${p}"
    fi
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

execute() {
  if ! "$@"
  then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

execute_sudo() {
  local -a args=("$@")
  if [[ -n "${SUDO_ASKPASS-}" ]]
  then
    args=("-A" "${args[@]}")
  fi
  if have_sudo_access
  then
    ohai "/usr/bin/sudo" "${args[@]}"
    system "/usr/bin/sudo" "${args[@]}"
  else
    ohai "${args[@]}"
    system "${args[@]}"
  fi
}

system() {
  if ! "$@"
  then
    warn "Failed during: $(shell_join "$@")"
    failed=true
  fi
}

####################################################################### script

homebrew_prefix_candidates=()

usage() {
  cat <<EOS
Homebrew Uninstaller
Usage: $0 [options]
    -p, --path=PATH  Sets Homebrew prefix. Defaults to ${homebrew_prefix_default}.
        --skip-cache-and-logs
                     Skips removal of HOMEBREW_CACHE and HOMEBREW_LOGS.
    -f, --force      Uninstall without prompting.
    -q, --quiet      Suppress all output.
    -n, --dry-run    Simulate uninstall but don't remove anything.
    -h, --help       Display this message.
EOS
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]
do
  case "$1" in
    -p*) homebrew_prefix_candidates+=("${1#-p}") ;;
    --path=*) homebrew_prefix_candidates+=("${1#--path=}") ;;
    --skip-cache-and-logs) opt_skip_cache_and_logs=1 ;;
    -f | --force) opt_force=1 ;;
    -q | --quiet) opt_quiet=1 ;;
    -d | -n | --dry-run) opt_dry_run=1 ;;
    -h | --help) usage ;;
    *)
      warn "Unrecognized option: '$1'"
      usage 1
      ;;
  esac
  shift
done

# Attempt to locate Homebrew unless `--path` is passed
if [[ "${#homebrew_prefix_candidates[@]}" -eq 0 ]]
then
  prefix="$(brew --prefix)"
  [[ -n "${prefix}" ]] && homebrew_prefix_candidates+=("${prefix}")
  prefix="$(command -v brew)" || prefix=""
  [[ -n "${prefix}" ]] && homebrew_prefix_candidates+=("$(dirname "$(dirname "$(strip_s "${prefix}")")")")
  homebrew_prefix_candidates+=("${homebrew_prefix_default}") # Homebrew default path
  homebrew_prefix_candidates+=("${HOME}/.linuxbrew")         # Linuxbrew default path
fi

HOMEBREW_PREFIX="$(
  for p in "${homebrew_prefix_candidates[@]}"
  do
    [[ -d "${p}" ]] || continue
    [[ ${p} == "${homebrew_prefix_default}" && -d "${p}/Homebrew/.git" ]] && echo "${p}" && break
    [[ -d "${p}/.git" || -x "${p}/bin/brew" ]] && echo "${p}" && break
  done
)"
[[ -n "${HOMEBREW_PREFIX}" ]] || abort "Failed to locate Homebrew!"

if [[ -d "${HOMEBREW_PREFIX}/.git" ]]
then
  HOMEBREW_REPOSITORY="$(dirname "$(realpath "${HOMEBREW_PREFIX}/.git")")"
elif [[ -x "${HOMEBREW_PREFIX}/bin/brew" ]]
then
  HOMEBREW_REPOSITORY="$(dirname "$(dirname "$(realpath "${HOMEBREW_PREFIX}/bin/brew")")")"
else
  abort "Failed to locate Homebrew!"
fi

if [[ -d "${HOMEBREW_PREFIX}/Cellar" ]]
then
  HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
else
  HOMEBREW_CELLAR="${HOMEBREW_REPOSITORY}/Cellar"
fi

if [[ -s "${HOMEBREW_REPOSITORY}/.gitignore" ]]
then
  gitignore="$(<"${HOMEBREW_REPOSITORY}/.gitignore")"
else
  gitignore="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/brew/HEAD/.gitignore)"
fi
[[ -n "${gitignore}" ]] || abort "Failed to fetch Homebrew .gitignore!"

{
  while read -r l
  do
    [[ "${l}" == \!* ]] || continue
    l="${l#\!}"
    l="${l#/}"
    [[ "${l}" == @(bin|share|share/doc) ]] && echo "REJECT: ${l}" >&2 && continue
    echo "${HOMEBREW_REPOSITORY}/${l}"
  done <<<"${gitignore}"

  if [[ "${HOMEBREW_PREFIX}" != "${HOMEBREW_REPOSITORY}" ]]
  then
    echo "${HOMEBREW_REPOSITORY}"
    directories=(
      bin/brew
      etc/bash_completion.d/brew
      share/doc/homebrew
      share/man/man1/brew.1
      share/man/man1/brew-cask.1
      share/man/man1/README.md
      share/zsh/site-functions/_brew
      share/zsh/site-functions/_brew_cask
      share/fish/vendor_completions.d/brew.fish
      var/homebrew
    )
    for p in "${directories[@]}"
    do
      echo "${HOMEBREW_PREFIX}/${p}"
    done
  else
    echo "${HOMEBREW_REPOSITORY}/.git"
  fi
  echo "${HOMEBREW_CELLAR}"
  echo "${HOMEBREW_PREFIX}/Caskroom"

  [[ -n ${opt_skip_cache_and_logs} ]] || cat <<-EOS
${HOME}/Library/Caches/Homebrew
${HOME}/Library/Logs/Homebrew
/Library/Caches/Homebrew
${HOME}/.cache/Homebrew
${HOMEBREW_CACHE:-}
${HOMEBREW_LOGS:-}
EOS

  if [[ "${ostype}" == macos ]]
  then
    dir_children "/Applications" "${HOME}/Applications" | while read -r p2; do
      [[ $(resolved_pathname "${p2}") == "${HOMEBREW_CELLAR}"/* ]] && echo "${p2}"
    done
  fi
} | while read -r l; do
  [[ -e "${l}" ]] && echo "${l}"
done | sort -u >"${tmpdir}/homebrew_files"
homebrew_files=()
while read -r l
do
  homebrew_files+=("${l}")
done <"${tmpdir}/homebrew_files"

if [[ -z "${opt_quiet}" ]]
then
  dry_str="${opt_dry_run:+would}"
  warn "This script ${dry_str:-will} remove:"
  pretty_print_pathnames "${homebrew_files[@]}"
fi

if [[ -t 0 && -z "${opt_force}" && -z "${opt_dry_run}" ]]
then
  read -rp "Are you sure you want to uninstall Homebrew? This will remove your installed packages! [y/N] "
  [[ "${REPLY}" == [yY]* ]] || abort
fi

[[ -n "${opt_quiet}" ]] || ohai "Removing Homebrew installation..."
paths=()
for p in Frameworks bin etc include lib opt sbin share var
do
  p="${HOMEBREW_PREFIX}/${p}"
  [[ -e "${p}" ]] && paths+=("${p}")
done
if [[ "${#paths[@]}" -gt 0 ]]
then
  if [[ "${ostype}" == macos ]]
  then
    args=(-E "${paths[@]}" -regex '.*/info/([^.][^/]*\.info|dir)')
  else
    args=("${paths[@]}" -regextype posix-extended -regex '.*/info/([^.][^/]*\.info|dir)')
  fi
  if [[ -n "${opt_dry_run}" ]]
  then
    args+=(-print)
    echo "Would delete:"
  else
    args+=(-exec /bin/bash -c)
    args+=("/usr/bin/install-info --delete --quiet {} \"\$(dirname {})/dir\"")
    args+=(';')
  fi
  system /usr/bin/find "${args[@]}"
  args=("${paths[@]}" -type l -lname '*/Cellar/*')
  if [[ -n "${opt_dry_run}" ]]
  then
    args+=(-print)
  else
    args+=(-exec unlink '{}' ';')
  fi
  [[ -n "${opt_dry_run}" ]] && echo "Would delete:"
  system /usr/bin/find "${args[@]}"
fi

for file in "${homebrew_files[@]}"
do
  if [[ -n "${opt_dry_run}" ]]
  then
    echo "Would delete ${file}"
  else
    if ! err="$(rm -fr "${file}" 2>&1)"
    then
      warn "Failed to delete ${file}"
      echo "${err}"
    fi
  fi
done

sudo() {
  ohai "/usr/bin/sudo" "$@"
  system /usr/bin/sudo "$@"
}

[[ -n "${opt_quiet}" ]] || ohai "Removing empty directories..."
paths=()
for p in bin etc include lib opt sbin share var Caskroom Cellar Homebrew Frameworks
do
  p="${HOMEBREW_PREFIX}/${p}"
  [[ -e "${p}" ]] && paths+=("${p}")
done
if [[ "${#paths[@]}" -gt 0 ]]
then
  if [[ "${ostype}" == macos ]]
  then
    args=("${paths[@]}" -name .DS_Store)
    if [[ -n "${opt_dry_run}" ]]
    then
      args+=(-print)
      echo "Would delete:"
    else
      args+=(-delete)
    fi
    execute_sudo /usr/bin/find "${args[@]}"
  fi
  args=("${paths[@]}" -depth -type d -empty)
  if [[ -n "${opt_dry_run}" ]]
  then
    args+=(-print)
    echo "Would remove directories:"
  else
    args+=(-exec rmdir '{}' ';')
  fi
  execute_sudo /usr/bin/find "${args[@]}"
fi

[[ -n "${opt_dry_run}" ]] && exit
if [[ "${HOMEBREW_PREFIX}" != "${homebrew_prefix_default}" && -e "${HOMEBREW_PREFIX}" ]]
then
  execute_sudo rmdir "${HOMEBREW_PREFIX}"
fi
if [[ "${HOMEBREW_PREFIX}" != "${HOMEBREW_REPOSITORY}" && -e "${HOMEBREW_REPOSITORY}" ]]
then
  execute_sudo rmdir "${HOMEBREW_REPOSITORY}"
fi

if [[ -z "${opt_quiet}" ]]
then
  if [[ "${failed}" == true ]]
  then
    warn "Homebrew partially uninstalled (but there were steps that failed)!"
    echo "To finish uninstalling rerun this script with \`sudo\`."
  else
    ohai "Homebrew uninstalled!"
  fi
fi

dir_children "${HOMEBREW_REPOSITORY}" "${HOMEBREW_PREFIX}" |
  sort -u >"${tmpdir}/residual_files"

if [[ -s "${tmpdir}/residual_files" && -z "${opt_quiet}" ]]
then
  echo "The following possible Homebrew files were not deleted:"
  while read -r f
  do
    pretty_print_pathnames "${f}"
  done <"${tmpdir}/residual_files"
  echo -e "You may wish to remove them yourself.\n"
fi

[[ "${failed}" != true ]]
