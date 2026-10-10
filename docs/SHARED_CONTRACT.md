# Shared contract

Both teams implement against this file. Do not invent parallel session shapes.

## Demo user

No auth for the hackathon.

```json
{ "id": "user_alex", "displayName": "Alex" }
```

## Canonical priority

```json
{
  "id": "task_1",
  "title": "Finalize Q3 Pitch Deck",
  "verification_type": "url",
  "verification_criteria": "Google Slides URL with 10 slides completed",
  "prep_actions": [
    "Open template in browser",
    "Summarize previous quarterly notes into bullet draft"
  ],
  "status": "not_started",
  "notes": "",
  "blocked": false
}
```

`verification_type`: `url` | `commit` | `text`  
`status`: `not_started` | `in_progress` | `done` | `forfeited`

## Session

```json
{
  "date": "2026-10-10",
  "status": "planned",
  "currentPriorityId": "task_1",
  "priorities": [],
  "artifacts": [],
  "events": [],
  "ledgerEntry": null,
  "voiceMemo": { "transcript": "", "targetDate": "2026-10-10" }
}
```

`status`: `planned` | `launched` | `in_progress` | `closed`

## Artifact

```json
{
  "id": "art_1",
  "priorityId": "task_1",
  "type": "url",
  "value": "https://github.com/org/repo/commit/4a9f12",
  "caption": "Auth flow merged",
  "verification": "unverified"
}
```

`verification`: `unverified` | `verified` | `failed`

## Ledger entry

Neutral copy only. No shame language.

```text
[Daily Proof-of-Work Record]
User: Alex
Commitment: Ship alpha auth flow
Status: VERIFIED
Artifact: github.com/org/repo/commit/4a9f12
```

Posted to `GET /api/ledger` and optionally a Discord/Slack webhook.

## HTTP API

| Method | Path | Owner | Notes |
|---|---|---|---|
| GET | `/health` | shared | `{ ok: true }` |
| GET | `/api/session?date=YYYY-MM-DD` | shared | Creates empty planned session if missing |
| PUT | `/api/session` | shared | Upsert priorities (manual editor) |
| POST | `/api/ingest` | Ledger | `{ transcript?, targetDate? }` → priorities |
| POST | `/api/launch` | Launchpad | Marks launched; returns launch plan |
| PATCH | `/api/priorities/:id` | Ledger | `{ status?, notes?, blocked? }` |
| POST | `/api/artifacts` | Ledger | Attach proof-of-work |
| POST | `/api/session/close` | Ledger | Pass/Fail, ledger row, optional next-day seed |
| GET | `/api/ledger` | Ledger | Public chronological feed |
| POST | `/api/ledger/publish` | Ledger | Webhook or dry-run log |
| POST | `/api/events` | Mirror stub | Store `distraction` \| `stuck` \| `break`; no UI |

## Launch plan (Launchpad response)

```json
{
  "focusUrl": "https://...",
  "referenceUrls": [],
  "sidecarUrl": "http://localhost:5173/launch/sidecar",
  "appsToMinimize": ["Steam", "Messages", "Twitter"],
  "hardKill": false,
  "preDraftMarkdown": "- ..."
}
```

Hard kill is **off** by default. Never target Discord, Chrome, or Cursor.

## Persistence

`data/store.json` on the API host. Seed a demo session on first boot if the file is missing.

## Route split (web)

- Launchpad owns `/launch` and `/launch/sidecar`
- Ledger owns `/progress` and `/ledger`
- Shared shell owns `/` (home / demo script)

## Mirror (out of scope)

Store `currentPriorityId` and accept `/api/events`. Do not poll windows or show Stuck vs Forfeit overlays until both teams convene.
