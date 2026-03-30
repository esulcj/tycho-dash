# Tycho Dashboard — Agent Rules

## Absolute Rules
- NO frameworks. Tailwind CSS + Alpine.js from CDN only.
- Light theme. White bg. Accent: #FD384E. System-ui font.
- Mobile-first. Min width 375px. Stacked cards.
- NO x-cloak on <body> — put it on the x-data div only.
- NO build step. Single index.html.
- Collector script: pure bash, no dependencies beyond coreutils + curl + jq.

## status.json Schema
```json
{
  "timestamp": "ISO-8601",
  "costs": {
    "today": 47.20,
    "session": 13.98,
    "dailyLimit": 200
  },
  "sessions": {
    "active": 3,
    "list": [
      {"channel": "#infrastructure", "turns": 42, "age": "2h"}
    ]
  },
  "emails": {
    "unread": 5,
    "oldest": "2d ago",
    "items": ["CLN & Deck (2d)", "RE: CloudNC growth round (2d)"]
  },
  "deploys": [
    {"name": "review.tycho.sh", "status": "up", "code": 302},
    {"name": "countingatoms.com", "status": "down", "code": 0}
  ],
  "gastown": {
    "daemon": "stopped",
    "rigs": 1,
    "lastBuild": "Outreach V2 — 15 min"
  },
  "system": {
    "uptime": "4d 12h",
    "diskFree": "100GB",
    "gatewayPid": 78965,
    "sessionCount": 14
  }
}
```

## Color Rules
- Cost bar: green (<50% of limit), yellow (50-80%), red (>80%)
- Deploys: green checkmark (2xx/3xx), red X (0/4xx/5xx)
- Emails: red badge if unread > 0, with ⚠️ if oldest > 24h
- Sessions: neutral (informational)

## Collector Script Contract
- Reads from: budget-status.js, sessions.json, himalaya, curl, gt CLI, system commands
- Writes to: stdout as JSON (caller redirects to status.json)
- MUST handle missing/broken sources gracefully — output "?" or null, never crash
- Curl timeouts: 5 seconds max per URL
- Exit 0 always (partial data is better than no data)
