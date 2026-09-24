#!/usr/bin/env bash

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

ensure_dir() {
  local mode=$1; shift
  if [[ $LVO_TEST_MODE == true ]]; then mkdir -p -- "$@"; else install -d -m "$mode" -- "$@"; fi
}

path() {
  if [[ -n $LVO_ROOT ]]; then printf '%s%s' "${LVO_ROOT%/}" "$1"; else printf '%s' "$1"; fi
}

sha_file() {
  [[ -f $1 ]] || { printf '-'; return; }
  sha256sum "$1" | awk '{print $1}'
}

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

utc_now() { date -u +%FT%TZ; }

require_platform() {
  local os_release
  os_release=$(path /etc/os-release)
  [[ -r $os_release ]] || die 'Cannot read /etc/os-release'
  local ID='' VERSION_ID=''
  # shellcheck disable=SC1090
  . "$os_release"
  [[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || die 'Only Debian 13 is supported'
  if [[ $LVO_TEST_MODE != true ]]; then
    [[ -d /run/systemd/system ]] || die 'A booted systemd is required'
    [[ $(uname -m) == x86_64 || $(uname -m) == aarch64 ]] || die 'Only amd64/arm64 is supported'
    has apt-get || die 'apt-get is required'
  fi
}

safe_token() { [[ $1 =~ ^[A-Za-z0-9._-]{16,128}$ ]]; }

read_meminfo_kib() {
  local key=$1
  awk -v key="$key" '$1 == key ":" {print $2; found=1} END {if (!found) print 0}' "$(path /proc/meminfo)"
}

percent_used() {
  local kind=${1:-blocks}
  if [[ $LVO_TEST_MODE == true && -n $LVO_ROOT ]]; then printf '10'; return; fi
  if [[ $kind == inodes ]]; then
    df -Pi / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
  else
    df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
  fi
}

read_file_privileged() {
  local file=$1
  if [[ -r $file ]]; then cat "$file"
  elif sudo -n test -r "$file" 2>/dev/null; then sudo -n cat "$file"
  fi
}

state_string_value() {
  local key=$1 state content
  state="$(path "$LVO_STATE_DIR")/state.json"
  content=$(read_file_privileged "$state" 2>/dev/null || true)
  sed -n 's/.*"'"$key"'":"\([^"]*\)".*/\1/p' <<< "$content" | head -n1
}

state_number_value() {
  local key=$1 state content
  state="$(path "$LVO_STATE_DIR")/state.json"
  content=$(read_file_privileged "$state" 2>/dev/null || true)
  sed -n 's/.*"'"$key"'":\([0-9][0-9]*\).*/\1/p' <<< "$content" | head -n1
}
