# Accountabilibrosis

Code Ada 2026 · **Off the Clock** · adaptive agentic accountability.

A Chief of Staff for deep work: **Launchpad** (morning staging) → **Mirror** (later) → **Public Ledger** (proof-of-work). Built as two parallel tracks that share one session contract.

## Why

Productivity tools fail when they need willpower you do not have, or when they punish you until you uninstall them. This loop pre-stages the workspace, tracks objective artifacts, and posts a neutral Pass/Fail record.

## Quick start

```bash
npm install
cp .env.example .env
npm run dev
```

- Web: http://localhost:5173
- API: http://localhost:3001/health

Open `/` and follow the demo path: ingest or use the seeded session → `/launch` → `/progress` → `/ledger`.

Optional: `DISCORD_WEBHOOK_URL` in `.env` to publish ledger rows. Without it, publish dry-runs to the API log.

macOS launch helper:

```bash
./desktop/macos/launch_workspace.sh
```

## Monorepo

| Path | Team | Role |
|---|---|---|
| `packages/shared` | both | Zod schemas |
| `apps/api` | both | Fastify + JSON store |
| `apps/web` | split by route | React UI |
| `desktop/macos` | Launchpad | Open / tile / focus |
| `docs/` | both | Team plans + contract |

## Docs

- [Shared contract](docs/SHARED_CONTRACT.md)
- [Team Launchpad](docs/TEAM_LAUNCHPAD.md)
- [Team Ledger](docs/TEAM_LEDGER.md)
- [Presentation](docs/PRESENTATION.md)
- [Architecture spec](project_architecture_specification.md)

## Track notes

Submit under **Off the Clock**. Midnight Saturday submission. Sunday 5-minute talk must include how we used Cursor / GrokBot. Mirror is the post-convene phase, not this weekend's demo-critical path.
