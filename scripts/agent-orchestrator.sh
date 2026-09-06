#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${OPANEL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
IMPLEMENTATION_DIR="$ROOT/docs/implementation"
RUN_CODEX="$SCRIPT_DIR/run-codex-review.sh"
RUN_CLAUDE="$SCRIPT_DIR/run-claude-fix.sh"
RUNTIME_DIR="${OPANEL_ORCHESTRATOR_RUNTIME_DIR:-${TMPDIR:-/tmp}/opanel-agent-orchestrator}"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

usage() {
  printf '%s\n' \
    "Usage: scripts/agent-orchestrator.sh dispatch" \
    "       scripts/agent-orchestrator.sh run M00" \
    "       scripts/agent-orchestrator.sh status M00"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    return 1
  }
}

state_file_for() {
  local milestone="$1"

  case "$milestone" in
    M[0-9][0-9]) printf '%s/%s/review-state.json\n' "$IMPLEMENTATION_DIR" "$milestone" ;;
    *) return 1 ;;
  esac
}

validate_state() {
  local state_file="$1"

  jq -e '
    (.milestone | type == "string" and test("^M[0-9]{2}$")) and
    (.status | IN(
      "implementing", "ready_for_review", "reviewing", "fix_required",
      "fixing", "accepted", "blocked", "human_acceptance"
    )) and
    (.reviewAttempt | type == "number" and . >= 0 and floor == .) and
    (.fixAttempt | type == "number" and . >= 0 and floor == .) and
    (.maxReviewAttempts | type == "number" and . > 0 and floor == .) and
    (.maxFixAttempts | type == "number" and . > 0 and floor == .)
  ' "$state_file" >/dev/null
}

write_state() {
  local state_file="$1"
  local filter="$2"
  local temporary
  shift 2

  temporary="$(mktemp "${state_file}.tmp.XXXXXX")"
  if ! jq "$@" "$filter" "$state_file" > "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  mv "$temporary" "$state_file"
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

block_state() {
  local state_file="$1"
  local reason="$2"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.status = "blocked" | .blockedReason = $reason | .lastError = $reason | .updatedAt = $now' \
    --arg reason "$reason" --arg now "$now"
  log "$(jq -r '.milestone' "$state_file") blocked: $reason"
}

begin_review() {
  local state_file="$1"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.status = "reviewing" | .reviewAttempt += 1 | .lastReviewer = "codex" |
     .verdict = null | .criticalCount = null | .highCount = null |
     .mediumCount = null | .lowCount = null | .lastError = null |
     .blockedReason = null | .updatedAt = $now' \
    --arg now "$now"
}

record_review() {
  local state_file="$1"
  local result="$2"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.lastReviewer = "codex" | .verdict = $verdict |
     .criticalCount = $critical | .highCount = $high |
     .mediumCount = $medium | .lowCount = $low | .updatedAt = $now' \
    --arg verdict "$(jq -r '.verdict' <<<"$result")" \
    --argjson critical "$(jq '.criticalCount' <<<"$result")" \
    --argjson high "$(jq '.highCount' <<<"$result")" \
    --argjson medium "$(jq '.mediumCount' <<<"$result")" \
    --argjson low "$(jq '.lowCount' <<<"$result")" \
    --arg now "$now"
}

set_fix_required() {
  local state_file="$1"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.status = "fix_required" | .updatedAt = $now' \
    --arg now "$now"
}

begin_fix() {
  local state_file="$1"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.status = "fixing" | .fixAttempt += 1 | .lastError = null | .updatedAt = $now' \
    --arg now "$now"
}

accept_for_human() {
  local state_file="$1"
  local now
  now="$(timestamp)"

  write_state "$state_file" \
    '.status = "accepted" | .acceptedAt = $now | .updatedAt = $now' \
    --arg now "$now"
  write_state "$state_file" \
    '.status = "human_acceptance" | .updatedAt = $now' \
    --arg now "$now"
  log "$(jq -r '.milestone' "$state_file") accepted by Codex; waiting for human acceptance"
}

acquire_lock() {
  local milestone="$1"
  local root_id lock_dir existing_pid

  mkdir -p "$RUNTIME_DIR"
  root_id="$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"
  lock_dir="$RUNTIME_DIR/${root_id}-${milestone}.lock"

  if ! mkdir "$lock_dir" 2>/dev/null; then
    existing_pid=""
    if [ -r "$lock_dir/pid" ]; then
      read -r existing_pid < "$lock_dir/pid" || true
    fi
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      return 1
    fi
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || return 1
    mkdir "$lock_dir" 2>/dev/null || return 1
  fi

  printf '%s\n' "$$" > "$lock_dir/pid"
  ORCHESTRATOR_LOCK_DIR="$lock_dir"
}

release_lock() {
  if [ -n "${ORCHESTRATOR_LOCK_DIR:-}" ]; then
    rm -f "$ORCHESTRATOR_LOCK_DIR/pid"
    rmdir "$ORCHESTRATOR_LOCK_DIR" 2>/dev/null || true
  fi
}

run_worker() {
  local milestone="$1"
  local state_file status review_result runner_status verdict
  local review_attempt fix_attempt max_reviews max_fixes

  state_file="$(state_file_for "$milestone")" || {
    log "invalid milestone: $milestone"
    return 2
  }
  [ -f "$state_file" ] || {
    log "missing review state: $state_file"
    return 2
  }
  validate_state "$state_file" || {
    log "invalid review state: $state_file"
    return 2
  }

  if ! acquire_lock "$milestone"; then
    log "$milestone already has an active orchestrator"
    return 0
  fi
  trap release_lock EXIT INT TERM

  while true; do
    validate_state "$state_file" || {
      block_state "$state_file" "INVALID_REVIEW_STATE"
      return 1
    }

    status="$(jq -r '.status' "$state_file")"
    review_attempt="$(jq -r '.reviewAttempt' "$state_file")"
    fix_attempt="$(jq -r '.fixAttempt' "$state_file")"
    max_reviews="$(jq -r '.maxReviewAttempts' "$state_file")"
    max_fixes="$(jq -r '.maxFixAttempts' "$state_file")"

    case "$status" in
      ready_for_review)
        if [ "$review_attempt" -ge "$max_reviews" ]; then
          block_state "$state_file" "MAX_REVIEW_ATTEMPTS_REACHED"
          return 1
        fi

        begin_review "$state_file"
        log "$milestone Codex review $((review_attempt + 1)) started"

        set +e
        review_result="$(OPANEL_ROOT="$ROOT" "$RUN_CODEX" "$milestone")"
        runner_status=$?
        set -e

        if [ "$runner_status" -ne 0 ] && [ "$runner_status" -ne 10 ]; then
          block_state "$state_file" "CODEX_REVIEW_EXECUTION_FAILED"
          return 1
        fi
        if ! jq -e '.verdict and (.criticalCount >= 0) and (.highCount >= 0)' \
          <<<"$review_result" >/dev/null 2>&1; then
          block_state "$state_file" "INVALID_CODEX_REVIEW_RESULT"
          return 1
        fi

        record_review "$state_file" "$review_result"
        verdict="$(jq -r '.verdict' <<<"$review_result")"

        if [ "$verdict" = "ACCEPTED" ]; then
          accept_for_human "$state_file"
          return 0
        fi

        review_attempt="$(jq -r '.reviewAttempt' "$state_file")"
        if [ "$review_attempt" -ge "$max_reviews" ]; then
          block_state "$state_file" "MAX_REVIEW_ATTEMPTS_REACHED"
          return 1
        fi
        set_fix_required "$state_file"
        ;;

      fix_required)
        if [ "$fix_attempt" -ge "$max_fixes" ]; then
          block_state "$state_file" "MAX_FIX_ATTEMPTS_REACHED"
          return 1
        fi

        begin_fix "$state_file"
        log "$milestone Claude fix $((fix_attempt + 1)) started"
        if ! OPANEL_ROOT="$ROOT" "$RUN_CLAUDE" "$milestone"; then
          block_state "$state_file" "CLAUDE_FIX_EXECUTION_FAILED"
          return 1
        fi

        status="$(jq -r '.status' "$state_file")"
        if [ "$status" != "ready_for_review" ]; then
          block_state "$state_file" "CLAUDE_FIX_DID_NOT_REQUEST_REVIEW"
          return 1
        fi
        ;;

      accepted)
        accept_for_human "$state_file"
        return 0
        ;;

      reviewing|fixing)
        block_state "$state_file" "INTERRUPTED_AGENT_PHASE"
        return 1
        ;;

      implementing|human_acceptance|blocked)
        return 0
        ;;
    esac
  done
}

dispatch() {
  local state_file milestone status log_file

  require_command jq || return 1
  mkdir -p "$RUNTIME_DIR"

  for state_file in "$IMPLEMENTATION_DIR"/M[0-9][0-9]/review-state.json; do
    [ -f "$state_file" ] || continue
    if ! validate_state "$state_file"; then
      log "ignoring invalid review state: $state_file"
      continue
    fi

    status="$(jq -r '.status' "$state_file")"
    case "$status" in
      ready_for_review|fix_required|reviewing|fixing|accepted) ;;
      *) continue ;;
    esac

    milestone="$(jq -r '.milestone' "$state_file")"
    log_file="$RUNTIME_DIR/${milestone}.log"
    if [ "${OPANEL_ORCHESTRATOR_FOREGROUND:-0}" = "1" ]; then
      run_worker "$milestone"
    else
      nohup env OPANEL_ROOT="$ROOT" OPANEL_ORCHESTRATOR_RUNTIME_DIR="$RUNTIME_DIR" \
        "$SCRIPT_DIR/agent-orchestrator.sh" run "$milestone" \
        >>"$log_file" 2>&1 </dev/null &
    fi
  done
}

main() {
  local command="${1:-dispatch}"

  case "$command" in
    dispatch)
      dispatch
      ;;
    run)
      [ "$#" -eq 2 ] || { usage >&2; return 2; }
      require_command jq
      run_worker "$2"
      ;;
    status)
      [ "$#" -eq 2 ] || { usage >&2; return 2; }
      jq . "$(state_file_for "$2")"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
