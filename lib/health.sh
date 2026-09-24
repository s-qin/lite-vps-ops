#!/usr/bin/env bash

health_float_ge() { awk -v value="$1" -v limit="$2" 'BEGIN {exit !(value >= limit)}'; }

health_classify_psi() {
  local metric=$1 avg10=$2 avg60=$3 avg300=$4 transient sustained long
  case "$metric" in
    memory) transient=5; sustained=2; long=1 ;;
    io) transient=15; sustained=5; long=2 ;;
    *) return 2 ;;
  esac
  if health_float_ge "$avg60" "$sustained" || health_float_ge "$avg300" "$long"; then
    printf 'WARN_SUSTAINED'
  elif health_float_ge "$avg10" "$transient"; then
    printf 'WARN_TRANSIENT'
  elif health_float_ge "$avg10" 0.5; then
    printf 'INFO'
  else
    printf 'PASS'
  fi
}

psi_value() {
  local window=$1 line=$2
  awk -v key="$window" '{for (i=1;i<=NF;i++) if ($i ~ ("^" key "=")) {split($i,a,"="); print a[2]; exit}}' <<< "$line"
}
