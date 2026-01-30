#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${AAPT2_BIN:-}" && -x "${AAPT2_BIN}" ]]; then
  bin="$AAPT2_BIN"
else
  bin=$(find "$HOME/.gradle/caches" -path "*aapt2-*-linux*/aapt2" | head -n 1)
fi

if [[ -z "${bin}" || ! -x "${bin}" ]]; then
  echo "aapt2 binary not found" >&2
  exit 1
fi

exec /usr/bin/qemu-x86_64 "$bin" "$@"
