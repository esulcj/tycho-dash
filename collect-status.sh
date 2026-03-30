#!/usr/bin/env bash
# collect-status.sh — Gather Tycho status into JSON on stdout
# Dependencies: coreutils, curl, jq
# Exit 0 always. Partial data is better than no data.

set -o pipefail

CURL_TIMEOUT=5

# ── Helpers ──────────────────────────────────────────────────────────

json_str() {
  # Escape a string for JSON output. Outputs "null" if empty.
  local val="$1"
  if [ -z "$val" ]; then
    echo "null"
  else
    printf '%s' "$val" | jq -Rs .
  fi
}

safe_read() {
  # Read a file, return empty string if missing/unreadable
  cat "$1" 2>/dev/null || true
}

# ── Timestamp ────────────────────────────────────────────────────────

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "?")

# ── Costs (from budget-status.js) ───────────────────────────────────

costs_today="null"
costs_session="null"
costs_daily_limit="null"

budget_file="${TYCHO_BUDGET_FILE:-budget-status.js}"
if [ -r "$budget_file" ]; then
  costs_today=$(jq -r '.today // empty' "$budget_file" 2>/dev/null || true)
  costs_session=$(jq -r '.session // empty' "$budget_file" 2>/dev/null || true)
  costs_daily_limit=$(jq -r '.dailyLimit // empty' "$budget_file" 2>/dev/null || true)
fi

# Ensure numeric or null
costs_today="${costs_today:-null}"
costs_session="${costs_session:-null}"
costs_daily_limit="${costs_daily_limit:-null}"

# ── Sessions (from sessions.json) ───────────────────────────────────

sessions_active=0
sessions_list="[]"

sessions_file="${TYCHO_SESSIONS_FILE:-sessions.json}"
if [ -r "$sessions_file" ]; then
  sessions_list=$(jq -c '.list // []' "$sessions_file" 2>/dev/null || echo "[]")
  sessions_active=$(echo "$sessions_list" | jq 'length' 2>/dev/null || echo 0)
fi

# ── Emails (via himalaya) ───────────────────────────────────────────

emails_unread=0
emails_oldest=""
emails_items="[]"

if command -v himalaya &>/dev/null; then
  # List unread emails as JSON
  email_json=$(himalaya envelope list --folder INBOX --filter new --output json 2>/dev/null || true)
  if [ -n "$email_json" ]; then
    emails_unread=$(echo "$email_json" | jq 'length' 2>/dev/null || echo 0)
    emails_items=$(echo "$email_json" | jq -c '[.[] | .subject // "no subject"] | .[0:10]' 2>/dev/null || echo "[]")
    # Calculate oldest unread age
    oldest_date=$(echo "$email_json" | jq -r 'sort_by(.date) | .[0].date // empty' 2>/dev/null || true)
    if [ -n "$oldest_date" ]; then
      oldest_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${oldest_date%%+*}" +%s 2>/dev/null \
                     || date -d "$oldest_date" +%s 2>/dev/null \
                     || true)
      if [ -n "$oldest_epoch" ]; then
        now_epoch=$(date +%s)
        age_secs=$((now_epoch - oldest_epoch))
        if [ "$age_secs" -ge 86400 ]; then
          emails_oldest="$((age_secs / 86400))d ago"
        elif [ "$age_secs" -ge 3600 ]; then
          emails_oldest="$((age_secs / 3600))h ago"
        else
          emails_oldest="$((age_secs / 60))m ago"
        fi
      fi
    fi
  fi
fi

# ── Deploys (via curl health checks) ────────────────────────────────

deploy_targets="${TYCHO_DEPLOY_TARGETS:-review.tycho.sh deck.tycho.sh countingatoms.com}"

deploys="[]"
for target in $deploy_targets; do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" "https://${target}" 2>/dev/null || echo "0")
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
    status="up"
  else
    status="down"
  fi
  deploys=$(echo "$deploys" | jq -c --arg name "$target" --argjson code "$http_code" --arg status "$status" \
    '. + [{"name": $name, "status": $status, "code": $code}]')
done

# ── Gas Town ────────────────────────────────────────────────────────

gt_daemon="unknown"
gt_rigs=0
gt_last_build=""

if command -v gt &>/dev/null; then
  gt_status=$(gt status --json 2>/dev/null || true)
  if [ -n "$gt_status" ]; then
    gt_running=$(echo "$gt_status" | jq -r '.running // false' 2>/dev/null || echo "false")
    if [ "$gt_running" = "true" ]; then
      gt_daemon="running"
    else
      gt_daemon="stopped"
    fi
    gt_rigs=$(echo "$gt_status" | jq '.rigs | length' 2>/dev/null || echo 0)
    gt_last_build=$(echo "$gt_status" | jq -r '.lastBuild // empty' 2>/dev/null || true)
  fi
fi

gt_daemon=$(json_str "$gt_daemon")
gt_last_build=$(json_str "$gt_last_build")
gt_rigs="${gt_rigs:-0}"

# ── System ──────────────────────────────────────────────────────────

sys_uptime=""
sys_disk_free=""
sys_gateway_pid="null"
sys_session_count=0

# Uptime
if [ "$(uname)" = "Darwin" ]; then
  boot_epoch=$(sysctl -n kern.boottime 2>/dev/null | awk '{gsub(/[^0-9]/," "); print $1}' || true)
  if [ -n "$boot_epoch" ]; then
    now_epoch=$(date +%s)
    up_secs=$((now_epoch - boot_epoch))
    up_days=$((up_secs / 86400))
    up_hours=$(( (up_secs % 86400) / 3600 ))
    sys_uptime="${up_days}d ${up_hours}h"
  fi
else
  sys_uptime=$(uptime -p 2>/dev/null || true)
fi

# Disk free
if command -v df &>/dev/null; then
  if [ "$(uname)" = "Darwin" ]; then
    disk_avail=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}')
    [ -n "$disk_avail" ] && sys_disk_free="${disk_avail}GB"
  else
    disk_avail=$(df -BG --output=avail / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $1}')
    [ -n "$disk_avail" ] && sys_disk_free="${disk_avail}GB"
  fi
fi

# Gateway PID (look for common gateway process names)
sys_gateway_pid=$(pgrep -f "tycho-gateway\|gateway" 2>/dev/null | head -1 || true)
sys_gateway_pid="${sys_gateway_pid:-null}"

# Session count (tmux or screen sessions)
if command -v tmux &>/dev/null; then
  sys_session_count=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ' || echo 0)
fi
sys_session_count="${sys_session_count:-0}"

# ── Assemble JSON ───────────────────────────────────────────────────

jq -n \
  --arg timestamp "$timestamp" \
  --argjson costs_today "$costs_today" \
  --argjson costs_session "$costs_session" \
  --argjson costs_daily_limit "$costs_daily_limit" \
  --argjson sessions_active "$sessions_active" \
  --argjson sessions_list "$sessions_list" \
  --argjson emails_unread "$emails_unread" \
  --argjson emails_items "$emails_items" \
  --argjson deploys "$deploys" \
  --argjson gt_daemon "$gt_daemon" \
  --argjson gt_rigs "$gt_rigs" \
  --argjson gt_last_build "$gt_last_build" \
  --arg emails_oldest "$emails_oldest" \
  --arg sys_uptime "$sys_uptime" \
  --arg sys_disk_free "$sys_disk_free" \
  --argjson sys_gw_pid "$sys_gateway_pid" \
  --argjson sys_sessions "$sys_session_count" \
'{
  "timestamp": $timestamp,
  "costs": {
    "today": $costs_today,
    "session": $costs_session,
    "dailyLimit": $costs_daily_limit
  },
  "sessions": {
    "active": $sessions_active,
    "list": $sessions_list
  },
  "emails": {
    "unread": $emails_unread,
    "oldest": (if $emails_oldest == "" then null else $emails_oldest end),
    "items": $emails_items
  },
  "deploys": $deploys,
  "gastown": {
    "daemon": $gt_daemon,
    "rigs": $gt_rigs,
    "lastBuild": $gt_last_build
  },
  "system": {
    "uptime": (if $sys_uptime == "" then null else $sys_uptime end),
    "diskFree": (if $sys_disk_free == "" then null else $sys_disk_free end),
    "gatewayPid": $sys_gw_pid,
    "sessionCount": $sys_sessions
  }
}'

exit 0
