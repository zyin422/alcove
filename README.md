# Accountabilibrosis 🚀
> **Adaptive Agentic Accountability System**  
> *Built for Code Ada 2026 — Flourish! (Off the Clock Track)*

[![Track](https://img.shields.io/badge/Track-Off%20the%20Clock-green.svg)](https://docs.x.ai)
[![AI Engine](https://img.shields.io/badge/AI%20Engine-SpaceXAI%20GrokBot-blue.svg)](https://x.ai)
[![Ecosystem](https://img.shields.io/badge/Powered%20By-Cursor%20%2F%20xAI-orange.svg)](https://cursor.com)

A Chief of Staff for deep work: **Launchpad** (morning staging) → **Mirror** (during deep work) → **Public Ledger** (proof-of-work). Built as two parallel subgroup tracks that share one session contract.

---

## 🔁 The Core Architecture Loop

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. THE LAUNCHPAD (Milestone 1 — Team Launchpad)                        │
│    • Morning trigger / laptop lid open detection                       │
│    • Full-screen "GrokBot is staging your workspace..." curtain        │
│    • Autonomous blank-page pre-drafting (repo, stubs, docs)            │
│    • Dual-zone AppleScript tiling (Zone A Focus 70% / Zone B Sidecar)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 2. THE MIRROR (Milestone 2 — Out of Scope for Hackathon Demo)          │
│    • Semantic drift classifier (distinguishes research vs distraction) │
│    • Metacognitive interrogation overlay ("Stuck vs Forfeiting")       │
│    • GrokBot real-time micro-triage (generates immediate next step)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 3. THE PUBLIC LEDGER (Milestone 3 — Team Ledger)                       │
│    • 60-second evening voice memo (completed vs incomplete priorities) │
│    • Objective artifact verification (Git PR diffs, commits, URLs)     │
│    • Unvarnished Discord/Slack webhook dispatch                        │
│    • Re-seeds tomorrow's Launchpad state                               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    └────────────── Loops back to 1 ─────┘
```

---

## 👥 Hackathon Team Subgroup Division

To maximize velocity during the hackathon, development is parallelized into two subgroups:

| Subgroup | Milestone Focus | Specification Document | Key Deliverables |
|---|---|---|---|
| **Subgroup Alpha** | **Milestone 1: The Launchpad** | [`docs/TEAM_LAUNCHPAD.md`](docs/TEAM_LAUNCHPAD.md) / [`docs/MILESTONE_1_LAUNCHPAD.md`](docs/MILESTONE_1_LAUNCHPAD.md) | Launch UI (`/launch`), Sidecar (`/launch/sidecar`), Launch plan generator (`POST /api/launch`), macOS window tiler (`desktop/macos/launch_workspace.sh`). |
| **Subgroup Beta** | **Milestone 3: The Public Ledger** | [`docs/TEAM_LEDGER.md`](docs/TEAM_LEDGER.md) / [`docs/MILESTONE_3_LEDGER.md`](docs/MILESTONE_3_LEDGER.md) | Voice memo ingestion (`POST /api/ingest`), Progress board (`/progress`), Public ledger (`/ledger`), Artifact verification, Webhook publisher. |
| **Shared** | **System Contracts** | [`docs/SHARED_CONTRACT.md`](docs/SHARED_CONTRACT.md) / [`docs/SHARED_CONTRACTS.md`](docs/SHARED_CONTRACTS.md) | Zod / JSON schemas, session state bridge between evening debrief and morning staging. |

---

## 📁 Monorepo Structure

```
accountabilibrosis/
├── apps/
│   ├── api/                            # Fastify backend & GrokBot agent orchestration
│   └── web/                            # React + Vite frontend (/launch, /progress, /ledger, /sidecar)
├── packages/
│   └── shared/                         # Shared Zod schemas & contracts
├── desktop/
│   ├── macos/                          # macOS AppleScript & focus automation scripts
│   └── windows/                        # Windows PowerShell bridge
├── docs/
│   ├── TEAM_LAUNCHPAD.md               # Subgroup Alpha roadmap & tasks
│   ├── TEAM_LEDGER.md                  # Subgroup Beta roadmap & tasks
│   ├── SHARED_CONTRACT.md              # Shared session & priority contracts
│   ├── PRESENTATION.md                 # 5-minute pitch script for Sunday
│   ├── MILESTONE_1_LAUNCHPAD.md        # Extended GrokBot Launchpad implementation plan
│   └── MILESTONE_3_LEDGER.md           # Extended GrokBot Ledger implementation plan
└── project_architecture_specification.md# Master technical architecture specification
```

---

## 🛠️ Quickstart

### 1. Prerequisites
- **Node.js 18+** & **npm**
- **macOS** (for AppleScript window automation)
- Optional: xAI API Key (`XAI_API_KEY`) for Grok models (`grok-4.6`, `grok-build-0.1`)
- Optional: `DISCORD_WEBHOOK_URL` to publish ledger rows

### 2. Install & Run
```bash
npm install
cp .env.example .env
npm run dev
```

- **Web App:** http://localhost:5173
- **API Server:** http://localhost:3001/health

Open `/` in your browser and follow the demo path:
1. Ingest audio/text memo (or load demo seed)
2. `/launch` → Launchpad staging & Zone B sidecar
3. `/progress` → In-flight task updates
4. `/ledger` → Public proof-of-work feed & Discord publish

### 3. macOS Desktop Launch Helper
```bash
./desktop/macos/launch_workspace.sh
```

---

## 🎯 Code Ada 2026 Presentation Alignment

- **Track:** Off the Clock (Everyday Life) — Tackles daily friction with personal productivity.
- **Required Tech:** Integrates SpaceXAI GrokBot & Cursor agentic workflows to eliminate activation energy.
- **Academic Foundation:**
  - *Choice Architecture* (Thaler & Sunstein): Default environment pre-staged for immediate action ($B = MAP$).
  - *Commitment Devices & Hawthorne Effect* (Schelling): Public, unvarnished proof-of-work logging without toxic nagging.
