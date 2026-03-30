#!/usr/bin/env bash
# collect-status.sh — Gather Tycho status into JSON on stdout
# Dependencies: coreutils, curl, jq
# Exit 0 always. Partial data is better than no data.

set -o pipefail

CURL_TIMEOUT=5
TODAY=$(date -u +%Y-%m-%d)

# ── Timestamp ────────────────────────────────────────────────────────

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

# ── Costs ────────────────────────────────────────────────────────────

costs_json='{"error":"budget file not found"}'
budget_file="$HOME/.openclaw/state/budget/today.json"

if [ -r "$budget_file" ]; then
  budget_date=$(jq -r '.date // empty' "$budget_file" 2>/dev/null || true)
  total_usd=$(jq -r '.total_usd // 0' "$budget_file" 2>/dev/null || echo "0")
  entries_count=$(jq '.entries | length' "$budget_file" 2>/dev/null || echo "0")

  if [ "$budget_date" != "$TODAY" ]; then
    costs_json=$(jq -n \
      --argjson totalUsd "$total_usd" \
      --argjson sessions "$entries_count" \
      --arg lastDate "$budget_date" \
      '{"totalUsd":$totalUsd,"dailyLimit":200,"sessions":$sessions,"stale":true,"lastDate":$lastDate}')
  else
    costs_json=$(jq -n \
      --argjson totalUsd "$total_usd" \
      --argjson sessions "$entries_count" \
      '{"totalUsd":$totalUsd,"dailyLimit":200,"sessions":$sessions,"stale":false,"lastDate":null}')
  fi
fi

# ── Deploy Health ────────────────────────────────────────────────────

deploys="[]"
deploy_urls="review.tycho.sh deck.tycho.sh outreach-v2.pages.dev tycho-dash.pages.dev countingatoms.com themissingleap.com"

for name in $deploy_urls; do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT" "https://${name}" 2>/dev/null || echo "0")
  if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -le 399 ] 2>/dev/null; then
    status="up"
  else
    status="down"
  fi
  deploys=$(echo "$deploys" | jq -c \
    --arg name "$name" \
    --arg url "https://${name}" \
    --argjson code "${http_code:-0}" \
    --arg status "$status" \
    '. + [{"name":$name,"url":$url,"code":$code,"status":$status}]')
done

# ── Email Queue ──────────────────────────────────────────────────────

emails_json='{"error":"himalaya unavailable"}'

if command -v himalaya &>/dev/null; then
  email_raw=$(himalaya -a fc list --page-size 20 -o json 2>/dev/null || true)

  if [ -n "$email_raw" ] && echo "$email_raw" | jq empty 2>/dev/null; then
    email_count=$(echo "$email_raw" | jq 'length' 2>/dev/null || echo "0")
    email_subjects=$(echo "$email_raw" | jq -c '[.[0:5] | .[].subject // "no subject"]' 2>/dev/null || echo "[]")
    emails_json=$(jq -n \
      --argjson count "$email_count" \
      --argjson subjects "$email_subjects" \
      '{"count":$count,"subjects":$subjects}')
  else
    # Fallback: text mode
    email_text=$(himalaya -a fc list --page-size 20 2>/dev/null || true)
    if [ -n "$email_text" ]; then
      line_count=$(echo "$email_text" | wc -l | tr -d ' ')
      email_count=$((line_count > 1 ? line_count - 1 : 0))
      emails_json=$(jq -n --argjson count "$email_count" '{"count":$count,"subjects":[]}')
    fi
  fi
fi

# ── Gastown ──────────────────────────────────────────────────────────

if command -v gt &>/dev/null; then
  rig_output=$(cd ~/gt && gt rig list 2>/dev/null || true)
  if [ -n "$rig_output" ]; then
    rig_count=$(echo "$rig_output" | grep -cE '^🟢|^🟡|^🔴|^●|^○' 2>/dev/null || echo "0")
    rig_raw=$(echo "$rig_output" | head -20)
    gastown_json=$(jq -n \
      --argjson rigs "$rig_count" \
      --arg raw "$rig_raw" \
      '{"installed":true,"rigs":$rigs,"raw":$raw}')
  else
    gastown_json='{"installed":true,"rigs":0,"raw":""}'
  fi
else
  gastown_json='{"installed":false}'
fi

# ── System ───────────────────────────────────────────────────────────

# Uptime: parse "up X days, HH:MM" from uptime output
sys_uptime=$(uptime 2>/dev/null | sed 's/.*up *//' | sed 's/,[^,]*load.*//' | sed 's/,[^,]*user.*//' | sed 's/^ *//' | sed 's/ *$//' || echo "unknown")

# Disk free
sys_disk_free=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

# Gateway
sys_gw_pid=$(pgrep -f "openclaw.*gateway" 2>/dev/null | head -1 || true)
if [ -n "$sys_gw_pid" ]; then
  sys_gw_status="running"
else
  sys_gw_pid="null"
  sys_gw_status="down"
fi

# ── Assemble JSON ────────────────────────────────────────────────────

jq -n \
  --arg timestamp "$timestamp" \
  --argjson costs "$costs_json" \
  --argjson deploys "$deploys" \
  --argjson emails "$emails_json" \
  --argjson gastown "$gastown_json" \
  --arg sysUptime "$sys_uptime" \
  --arg sysDisk "$sys_disk_free" \
  --argjson sysGwPid "${sys_gw_pid}" \
  --arg sysGwStatus "$sys_gw_status" \
'{
  "timestamp": $timestamp,
  "costs": $costs,
  "deploys": $deploys,
  "emails": $emails,
  "gastown": $gastown,
  "system": {
    "uptime": $sysUptime,
    "diskFree": $sysDisk,
    "gatewayPid": $sysGwPid,
    "gatewayStatus": $sysGwStatus
  }
}'

exit 0
