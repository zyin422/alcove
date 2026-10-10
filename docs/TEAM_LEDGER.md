# Team Ledger / progress

**Phase:** during-day tracking + end-of-day public record  
**Judging hook:** user engagement + technical development — a visible, non-shaming proof-of-work loop.  
**Out of scope:** live window polling (The Mirror).

## Goal

Objective artifacts in, neutral Pass/Fail out. Night memo seeds tomorrow's Launchpad. Public `/ledger` works even if Discord is down.

## Owners

Fill names at the event.

- Ingest (`POST /api/ingest`, recorder + textarea)
- Progress board (`/progress`)
- Artifacts
- Session close
- Public ledger (`/ledger`)
- Webhook publisher

## Build order

1. Textarea ingest (required). Web Speech / file upload is optional enhancement — halls are loud.
2. Parse transcript into up to 3 priorities (LLM if `OPENAI_API_KEY` / similar exists; else numbered-line heuristic).
3. Progress board: status chips, notes, blocked flag via `PATCH /api/priorities/:id`.
4. Artifact form: url / commit / text. Optional HEAD check; never block on network failure — mark `UNVERIFIED`.
5. Close ritual: one button, not a 5pm cron. Per priority `VERIFIED` | `UNVERIFIED` | `FAIL`. Neutral copy.
6. `GET /api/ledger` page for judges.
7. `POST /api/ledger/publish` to `DISCORD_WEBHOOK_URL` or dry-run log the payload.
8. On close, if a memo targets tomorrow, write `sessions[tomorrow]`.

## Ledger template

```text
[Daily Proof-of-Work Record]
User: Alex
Commitment: Ship alpha auth flow
Status: VERIFIED
Artifact: github.com/org/repo/commit/4a9f12
```

## Done when

Typed memo → priorities exist → attach a GitHub URL → close → `/ledger` shows Pass/Fail and a webhook fires (or the server logs the payload).

## Files

- `apps/web/src/pages/Progress.tsx`
- `apps/web/src/pages/Ledger.tsx`
- `apps/api/src/ingest.ts`
- `apps/api/src/ledger.ts`
