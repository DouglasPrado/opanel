#!/usr/bin/env bash
# Shared helpers for the opanel-loop state scripts.
#
# Both state files are read by hooks that can fire concurrently — a Stop hook
# while a subagent is still writing, two tool calls in the same turn — so every
# write goes through with_lock and lands atomically via a temp file plus mv.
#
# flock is the right tool and is used when present. macOS ships no flock, and a
# plugin that only works on Linux is a plugin that does not work here, so the
# fallback is an atomic mkdir with a liveness check on the recorded pid — the
# same technique the orchestrator this replaces used for the same reason.

set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 2; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

# with_lock <lock-path> <command...>
with_lock() {
  local lock="$1"; shift
  mkdir -p "$(dirname "$lock")"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock.flock"
    flock 9
    "$@"
    local rc=$?
    exec 9>&-
    return $rc
  fi

  local dir="$lock.lockdir" waited=0 pid=""
  while ! mkdir "$dir" 2>/dev/null; do
    pid=""
    [ ! -r "$dir/pid" ] || read -r pid < "$dir/pid" || true
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$dir/pid"; rmdir "$dir" 2>/dev/null || true
      continue
    fi
    waited=$((waited + 1))
    [ "$waited" -lt 100 ] || die "could not acquire lock: $dir"
    sleep 0.1
  done
  printf '%s\n' "$$" > "$dir/pid"
  # shellcheck disable=SC2064
  trap "rm -f '$dir/pid'; rmdir '$dir' 2>/dev/null || true" EXIT INT TERM

  "$@"
}

# write_json <file> <jq-filter> [jq args...]
# Never edits in place: a crashed jq must not leave a truncated state file.
write_json() {
  local file="$1"; shift
  local filter="$1"; shift
  local tmp
  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  if ! jq "$@" "$filter" "$file" > "$tmp"; then
    rm -f "$tmp"
    die "failed to update $file"
  fi
  [ -s "$tmp" ] || { rm -f "$tmp"; die "refusing to write an empty $file"; }
  mv "$tmp" "$file"
}

now_utc() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# milestone_dir_arg <path> — normalise and validate a milestone directory.
milestone_dir_arg() {
  local dir="${1:-}"
  [ -n "$dir" ] || die "usage: $(basename "$0") <milestone-dir> <command> [args]"
  dir="${dir%/}"
  [ -d "$dir" ] || die "no such milestone directory: $dir"
  printf '%s\n' "$dir"
}

milestone_id_from_dir() { basename "$1"; }
