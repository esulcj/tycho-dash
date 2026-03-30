# Tycho Dashboard v2 — Full Specification

## Goals
Give Theo a single URL he opens on his phone to see everything Tycho is doing, what it costs, and what needs attention. No clicking, no asking Discord. Glanceable.

## User Stories
1. I open the URL and immediately see today's cost with a visual bar showing % of $200 limit.
2. I see which deploys are healthy (green) and which are down (red) without scrolling.
3. I see how many emails are waiting and how old the oldest one is.
4. I see what Gastown has built recently.
5. I see system health: uptime, disk, gateway status.
6. The page auto-refreshes. If data is stale (>10 min), I see a warning.
7. On mobile (375px) everything stacks cleanly with no horizontal scroll.

## Data Source Specifications

### Cost Data
- **Source file**: `~/.openclaw/state/budget/today.json`
- **Format**: `{ "date": "YYYY-MM-DD", "total_usd": float, "entries": [...] }`
- **Known issue**: File date may be stale (e.g. shows Feb when it's March). Check: if `date` field != today, the budget tracker isn't running. Show "Budget tracker offline" instead of $0.
- **Fallback**: Parse `entries` array length for session count.
- **Daily limit**: Hardcoded $200 (from MEMORY.md).
- **Session cost**: Sum entries where `session_id` matches the most recent session, or just show total.

### Deploy Health
- **URLs to check** (hardcoded list):
  - `https://review.tycho.sh` — expect 302 (CF Access redirect = healthy)
  - `https://deck.tycho.sh` — expect 302
  - `https://outreach-v2.pages.dev` — expect 200 or 302 (CF Access)
  - `https://tycho-dash.pages.dev` — expect 200 or 302
  - `https://countingatoms.com` — currently down, expect 0/timeout
  - `https://themissingleap.com` — status unknown
- **Command**: `curl -s -o /dev/null -w "%{http_code}" --max-time 5 <URL>`
- **Healthy**: HTTP 200, 301, 302, 303. **Down**: 0, 4xx, 5xx.

### Email Queue
- **Command**: `himalaya -a fc list --page-size 20 -o json 2>/dev/null`
- **If himalaya fails** (auth expired, not installed): Output `{"unread": "?", "error": "himalaya unavailable"}`
- **Parse**: Count messages, find oldest date, list subjects.
- **Fallback if -o json not supported**: `himalaya -a fc list --page-size 20 2>/dev/null` and parse text table.

### Gastown Status
- **Command**: `cd ~/gt && gt rig list 2>/dev/null`
- **Parse**: Rig names, polecat counts, running/stopped status.
- **If gt not found**: `{"status": "not installed"}`
- **If no rigs**: `{"rigs": 0}`

### System Health
- **Uptime**: `uptime` — parse "up X days, HH:MM" portion
- **Disk**: `df -h / | tail -1` — parse available column (4th field)
- **Gateway PID**: `pgrep -f "openclaw.*gateway" | head -1`
- **If PID not found**: Gateway is down, show red.
- **Gateway sessions**: Not available via CLI without API. Hardcode "check /status" or omit.

## Collector Script Contract
- **Input**: None (reads from system)
- **Output**: JSON to stdout
- **Exit code**: Always 0
- **Error handling**: Every section wrapped in its own try. If one source fails, others still populate. Failed sections get `"error": "description"` instead of data.
- **Timeout**: Total script must complete in <30 seconds.

## Frontend Contract
- Reads `status.json` via fetch (same-origin)
- Auto-refreshes every 60 seconds
- Shows "Updated X min ago" from `timestamp` field
- If `timestamp` is >10 minutes old, show amber warning bar
- If fetch fails, show "Offline — last data from X"
- Color coding:
  - Cost bar: green (<50%), yellow (50-80%), red (>80%)
  - Deploys: ✅ (healthy), ❌ (down), ⚠️ (unknown/timeout)
  - Emails: red badge if >0, ⚠️ if oldest >24h
- Mobile-first: 375px min, stacked cards, no horizontal scroll
- Light theme, white bg, #FD384E accent, system-ui font
- Tailwind CDN + Alpine.js CDN, NO frameworks
- NO x-cloak on body (put on x-data div only)
