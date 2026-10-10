# Accountabilibrosis 🚀
> **Adaptive Agentic Accountability System**  
> *Built for Code Ada 2026 — Flourish! (Off the Clock Track)*

[![Track](https://img.shields.io/badge/Track-Off%20the%20Clock-green.svg)](https://docs.x.ai)
[![AI Engine](https://img.shields.io/badge/AI%20Engine-SpaceXAI%20GrokBot-blue.svg)](https://x.ai)
[![Ecosystem](https://img.shields.io/badge/Powered%20By-Cursor%20%2F%20xAI-orange.svg)](https://cursor.com)

Accountabilibrosis is an agentic Chief of Staff designed on a closed daily feedback loop. It eliminates the cognitive friction of starting your workday, replaces punitive blockers with metacognitive awareness, and enforces objective, Hawthorne-effect proof-of-work.

---

## 🔁 The Core Architecture Loop

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. THE LAUNCHPAD (Milestone 1 — Subgroup Alpha)                        │
│    • Morning trigger / laptop lid open detection                       │
│    • Full-screen "GrokBot is staging your workspace..." curtain        │
│    • Autonomous blank-page pre-drafting (repo, stubs, docs)            │
│    • Dual-zone AppleScript tiling (Zone A Focus 70% / Zone B Sidecar)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 2. THE MIRROR (Milestone 2 — In-Flight Deep Work)                      │
│    • Semantic drift classifier (distinguishes research vs distraction) │
│    • Metacognitive interrogation overlay ("Stuck vs Forfeiting")       │
│    • GrokBot real-time micro-triage (generates immediate next step)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 3. THE PUBLIC LEDGER (Milestone 3 — Subgroup Beta)                     │
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
| **Subgroup Alpha** | **Milestone 1: The Launchpad** | [`docs/MILESTONE_1_LAUNCHPAD.md`](docs/MILESTONE_1_LAUNCHPAD.md) | Wake detector, Full-screen staging curtain, GrokBot cold-start pre-drafting, macOS AppleScript dual-zone window tiler. |
| **Subgroup Beta** | **Milestone 3: The Public Ledger** | [`docs/MILESTONE_3_LEDGER.md`](docs/MILESTONE_3_LEDGER.md) | 60s Voice Memo recorder UI, Grok STT priority reconciler, Git/URL artifact auditor, Discord/Slack webhook publisher. |
| **Shared** | **System Contracts** | [`docs/SHARED_CONTRACTS.md`](docs/SHARED_CONTRACTS.md) | Data schemas (`session_state.json`, `launch_manifest.json`, `ledger_audit.json`). |

---

## 📁 Repository Structure

```
accountabilibrosis/
├── README.md                           # Team roadmap & setup guide
├── project_architecture_specification.md# Master technical architecture spec
├── docs/
│   ├── MILESTONE_1_LAUNCHPAD.md        # Subgroup Alpha detailed plan & tasks
│   ├── MILESTONE_3_LEDGER.md           # Subgroup Beta detailed plan & tasks
│   └── SHARED_CONTRACTS.md             # Shared JSON schemas between M1 and M3
├── backend/
│   ├── app.py                          # FastAPI gateway & WebSocket hub
│   ├── config.py                       # Settings & xAI API configuration
│   ├── services/
│   │   ├── grok_agent.py               # GrokBot client (xai-sdk / api.x.ai/v1)
│   │   ├── launchpad_service.py        # M1: Priority decomposition & stub generator
│   │   ├── ledger_service.py           # M3: Voice memo reconciliation & state seed
│   │   ├── artifact_auditor.py         # M3: Git diff & URL validator
│   │   └── webhook_dispatcher.py       # M3: Discord / Slack publisher
│   └── tests/
├── frontend/
│   ├── index.html                      # App portal
│   ├── curtain.html                    # M1: Full-screen "GrokBot is staging..." curtain
│   ├── sidecar.html                    # M1: Zone B persistent companion widget
│   ├── ledger.html                     # M3: 60s voice recorder & evening review
│   └── static/
│       ├── css/style.css
│       └── js/
│           ├── audio_recorder.js       # M3: Web Audio / MediaRecorder
│           └── sidecar.js              # M1: Countdown timer & unblocker
├── scripts/
│   ├── wake_detector.py                # M1: Laptop lid / wake heartbeat daemon
│   └── tile_workspace.applescript      # M1: macOS window arranger (Zone A/B)
└── data/
    └── session_state.json              # Shared loop persistence
```

---

## 🛠️ Quickstart & Prerequisites

### 1. Environment Requirements
- **macOS** (for AppleScript window automation)
- **Python 3.10+**
- **xAI API Key** (`XAI_API_KEY`) for Grok models (`grok-4.6`, `grok-build-0.1`)
- Optional: Discord / Slack Webhook URL for Public Ledger posting

### 2. Setup
```bash
# Clone the repository
git clone https://github.com/zyin422/accountabilibrosis.git
cd accountabilibrosis

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install fastapi uvicorn xai-sdk httpx pydantic python-dotenv
```

### 3. Environment Variables
Create a `.env` file in the root directory:
```env
XAI_API_KEY=your_xai_api_key_here
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
WORKSPACE_ROOT=/path/to/your/projects
```

---

## 🎯 Code Ada 2026 Presentation Alignment

- **Track:** Off the Clock (Everyday Life) — Tackles daily cognitive friction with personal productivity.
- **Required Tech:** Integrates SpaceXAI GrokBot & Cursor agentic workflows to eliminate activation energy.
- **Academic Foundation:**
  - *Choice Architecture* (Thaler & Sunstein): Default environment pre-staged for immediate action ($B = MAP$).
  - *Commitment Devices & Hawthorne Effect* (Schelling): Public, unvarnished proof-of-work logging without toxic nagging.
