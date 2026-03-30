# Tycho Dashboard — Agent Contracts

## Absolute Rules
- NO frameworks. Tailwind CSS + Alpine.js from CDN only.
- Light theme. White bg. Accent: #FD384E. System-ui font.
- Mobile-first. Min width 375px. Stacked cards.
- NO x-cloak on body tag. Put it on the x-data div only.
- NO build step. Single index.html + collect-status.sh + status.json.

## Collector Script: collect-status.sh

Must produce JSON to stdout. Exit 0 always. Each section independently wrapped so one failure doesn't kill others.

### Cost Data
- File: `$HOME/.openclaw/state/budget/today.json`
- Schema: `{ "date": "YYYY-MM-DD", "total_usd": float, "entries": [...] }`
- If `date` field != today (via `date -u +%Y-%m-%d`): data is stale. Set `"stale": true` and `"lastDate": "<value>"`.
- If file missing: `{"error": "budget file not found"}`
- Daily limit is hardcoded 200 (dollars).
- Session count = length of entries array.

### Deploy Health
Check each URL with: `curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "0"`

URLs (hardcoded):
- review.tycho.sh (expect 302)
- deck.tycho.sh (expect 302)
- outreach-v2.pages.dev (expect 200 or 302)
- tycho-dash.pages.dev (expect 200 or 302)
- countingatoms.com (likely timeout/0)

Status logic: code 200-399 = "up". Anything else = "down".

Output per deploy: `{"name": "review.tycho.sh", "url": "https://review.tycho.sh", "code": 302, "status": "up"}`

### Email Queue
- Command: `himalaya -a fc list --page-size 20 -o json 2>/dev/null`
- If himalaya fails or empty: try `himalaya -a fc list --page-size 20 2>/dev/null` and count lines (minus header)
- If both fail: `{"error": "himalaya unavailable"}`
- Parse: count of messages, first 5 subjects

### Gastown
- Check: `command -v gt`
- If installed: `cd ~/gt && gt rig list 2>/dev/null`
- Count rigs by grepping for lines starting with bullet/circle characters
- Output: `{"installed": true, "rigs": 2, "raw": "<first 20 lines>"}`
- If not installed: `{"installed": false}`

### System
- Uptime: `uptime` then parse the "up X days, HH:MM" part with sed
- Disk free: `df -h / | tail -1 | awk '{print $4}'`
- Gateway PID: `pgrep -f "openclaw.*gateway" | head -1`
- Gateway status: "running" if PID found, "down" if not

### Final Assembly
Use `jq -n` with `--argjson` for each section to build the final JSON cleanly. Never use string concatenation for JSON.

The timestamp field: `date -u +%Y-%m-%dT%H:%M:%SZ`

## Frontend: index.html

### Data Flow
1. On load: `fetch("status.json")`, parse, render all sections
2. Every 60s: re-fetch, update all sections
3. On fetch error: show "Offline" amber banner with last good timestamp

### Color Rules
- Cost bar: green if <50% of dailyLimit, yellow 50-80%, red >80%
- If costs.stale is true: "Budget tracker offline since {lastDate}" in amber
- If costs.error: "Budget data unavailable" in gray
- Deploys: green checkmark + green text (up), red X + red text (down)
- Emails: red badge showing count if unread > 0. Amber warning if oldest > 24h.
- If emails.error: "Email check unavailable" in gray

### Layout (mobile-first, 375px min)
Stacked cards with 1rem gap.
Each card: white bg, subtle border (gray-200), rounded-lg, p-4.
Header: "⚡ Tycho Status" bold + "Updated X min ago" in gray text.
Card order: Cost, Deploys, Emails, Gastown, System.
No horizontal scrolling. Everything wraps or truncates.
