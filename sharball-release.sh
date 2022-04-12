#!/bin/bash

# We don't need return codes for "$(command)", only stdout is needed.
# Allow `[[ -n "$(command)" ]]`, `func "$(command)"`, pipes, etc.
# shellcheck disable=SC2312

set -u

abort() {
  printf "%s\n" "$@"
  exit 1
}

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]
then
  abort "Bash is required to interpret this script."
fi

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
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

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

line_range_of() {
  # Usage: line_range_of file start end
  head -n +"$3" "$1" | tail -n +"$2"
}

curl() {
  command curl -fSL --retry "${HOMEBREW_CURL_RETRIES:-3}" "$@"
}

wait_for() {
  local MESSAGE="$2" TIME="$1" t s="s"
  echo "${MESSAGE}" >&2
  echo -ne "\033[?25l" >&2
  for ((t = TIME; t > 0; --t))
  do
    ((t > 1)) || s=""
    echo -ne "Wait for ${t} second${s}.\033[K\r" >&2
    sleep 1
  done
  echo -ne "\033[K\033[?25h" >&2
}

get_latest_version() {
  # Usage: get_latest_version repo timeout
  local REPO="$1" VERSION=""
  local TIMEOUT="${2:-300}"
  local TIME=0 INTERVAL=1 t

  while true
  do
    ((TIME > 0)) && echo "Retrying..." >&2

    VERSION="$(
      curl --silent --connect-timeout 10 "https://api.github.com/repos/${REPO}/releases/latest" |
        grep '"tag_name":' |
        sed -E 's/^.*: *"([^"]+)",?$/\1/'
    )"
    if [[ -n "${VERSION}" ]] || ((TIME >= TIMEOUT))
    then
      break
    fi

    wait_for "${INTERVAL}" "Failed to find latest release of ${REPO}."
    TIME="$((TIME + INTERVAL))"
    INTERVAL="$((INTERVAL * 2))"
  done

  echo "${VERSION}"
  [[ -n "${VERSION}" ]]
}

# Create temporary directory
TMP_DIR="$(mktemp -d -t brew-install.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPO="Homebrew/brew"
ohai "Querying for latest release of ${REPO}..."
TAG="$(get_latest_version "${REPO}")"

if [[ -z "${TAG}" ]]
then
  abort "Failed to find latest release of ${REPO}. Please check your Internet connection and try again."
fi

echo "Found release version ${TAG} of ${REPO}."

TARBALL="${TMP_DIR}/Homebrew-${TAG}.tar.gz"
(
  cd "${TMP_DIR}" || exit 1
  ohai "Downloading the latest release of ${REPO}@${TAG}..."
  curl --progress-bar --connect-timeout 30 "https://api.github.com/repos/${REPO}/tarball/${TAG}" >"${TARBALL}"
) || exit 1
SHA256="$(shasum -a 256 "${TARBALL}" | cut -d' ' -f1)"

OUTPUT_FILE="Homebrew-${TAG}.sh"

cat <<EOF
NAME:   Homebrew/brew
TAG:    ${TAG}
SHA256: ${SHA256}
EOF

THIS_DIR="$(
  cd "$(dirname "$0")" || exit 1
  pwd -P
)" || exit 1
if [[ -f "${THIS_DIR}/install.sh" ]]
then
  TEMPLATE="${THIS_DIR}/install.sh"
else
  TEMPLATE="${TMP_DIR}/install.sh"
  curl --silent --connect-timeout 30 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh >"${TEMPLATE}"
fi

shebang_lineno="$(grep -anm 1 -E '\s*# @@SHEBANG@@$' "${TEMPLATE}" | cut -d':' -f1)"
install_start_lineno="$(grep -anm 1 -E '\s*# @@INSTALL-START@@$' "${TEMPLATE}" | cut -d':' -f1)"
install_end_lineno="$(grep -anm 1 -E '\s*# @@INSTALL-END@@$' "${TEMPLATE}" | cut -d':' -f1)"
end_lineno="$(grep -anm 1 -E '\s*# @@END-HEADER@@$' "${TEMPLATE}" | cut -d':' -f1)"

shebang="$(
  cat <<EOF
#!/bin/bash

# NAME:   Homebrew/brew
# TAG:    ${TAG}
# SHA256: ${SHA256}
EOF
)"

extractor="$(
  cat <<EOF
  # @@EXTRACTOR-START@@
  ohai "Installing Homebrew..."

  # Verify the SHA256 checksum of the tarball appended to this script
  HEADER_LINES="\$(grep -anm 1 -E '\\s*# @@END-HEADER@@\$' "\${THIS_FILE}" | cut -d':' -f1)"
  SHA256="\$(tail -n +"\$((HEADER_LINES + 1))" "\${THIS_FILE}" | shasum -a 256 - | cut -d' ' -f1)"
  [[ "\${SHA256}" == "${SHA256}" ]] || abort "\$(
    cat <<EOABORT
  WARNING: SHA256 checksum mismatch of tar archive
  expected: ${SHA256}
       got: \${SHA256}
EOABORT
  )"

  ohai "Extacting tarball archive to \${HOMEBREW_REPOSITORY}..."
  tail -n +"\$((HEADER_LINES + 1))" "\${THIS_FILE}" |
    tar -xz --strip-components=1 -C "\${HOMEBREW_REPOSITORY}"
  # @@EXTRACTOR-END@@
EOF
)"

{
  echo "${shebang}"
  line_range_of "${TEMPLATE}" "$((shebang_lineno + 1))" "$((install_start_lineno - 1))"
  echo "${extractor}"
  line_range_of "${TEMPLATE}" "$((install_end_lineno + 1))" "${end_lineno}"
  cat "${TARBALL}"
} >"${OUTPUT_FILE}" # Homebrew-<tag>.sh

chmod +x "${OUTPUT_FILE}"
ln -f "${OUTPUT_FILE}" Homebrew-latest.sh # make hardlink with a constant name (Homebrew-latest.sh)

ohai "Successfully created Homebrew/brew ${TAG} installer to ${THIS_DIR}/${OUTPUT_FILE}."
