# Project Specification: Adaptive Agentic Accountability System

## 1. Executive Summary & Philosophy
Most productivity systems fail because they rely on executive function precisely when the user's willpower is depleted. Traditional accountability systems fall into two traps:
- **Toothless Nagging:** Automated push notifications and group chat alerts that are easily ignored and breed annoyance.
- **Punitive Blockers:** Hard locks and financial penalties that provoke psychological reactance, leading users to uninstall the software.

This project reframes the agent not as a hall monitor, but as an **autonomous Chief of Staff** operating on a closed daily feedback loop. It minimizes the activation energy needed to begin, disrupts mindless task-switching mid-flight, and enforces transparent, artifact-based proof-of-work.

---

## 2. The 3-Phase Daily Loop

```
┌─────────────────────────────────────────────────────────────┐
│ 1. THE LAUNCHPAD (Morning / Pre-Session)                   │
│    • Closes recreational processes & silences notifications │
│    • Tiles target workspaces side-by-side                   │
│    • Pre-drafts documents & extracts initial context        │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. THE MIRROR (During Deep Work)                            │
│    • Detects tab/app drift in real time                     │
│    • Forces metacognitive justification (Stuck vs. Forfeit) │
│    • Breaks cognitive trance without hostile blocking       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. THE PUBLIC LEDGER (End of Day / Session Close)           │
│    • Validates objective proof-of-work (PRs, URLs, diffs)   │
│    • Posts neutral status (Pass/Fail) to shared channel     │
│    • Ingests 60s voice memo to seed tomorrow's Launchpad    │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               └───────── Loops back to 1 ─────┘
```

---

## 3. Academic & Behavioral Grounding

| Phase | Mechanism | Theoretical Foundation | Core Principle |
|---|---|---|---|
| **Phase 1: The Launchpad** | Environment pre-staging, blank-page pre-filling | **Choice Architecture** (Thaler & Sunstein) & **Ego Depletion** (Baumeister) | Motivation fluctuates; by designing the default environment for immediate action, starting shifts from high-friction creation to low-friction editing ($B = MAP$). |
| **Phase 2: The Mirror** | Real-time context-switch interrogation | **Implementation Intentions** (Gollwitzer) & **Metacognitive Monitoring** (Flavell) | Hard blocks cause reactance (Brehm); gentle metacognitive friction forces conscious acknowledgement of avoidance, breaking mindless automaticity. |
| **Phase 3: The Public Ledger** | Artifact validation & transparent status logging | **Commitment Devices** (Schelling) & **The Hawthorne Effect** | Public, neutral exposure of objective outcomes creates skin in the game without toxic or emotional shaming. |

---

## 4. System Architecture & Components

```
                ┌─────────────────────────────────┐
                │        Client Interfaces        │
                │  • Web Companion / Tray App     │
                │  • Audio Recorder (Web Speech)  │
                └───────────────┬─────────────────┘
                                │
                                ▼
                ┌─────────────────────────────────┐
                │          Backend API            │
                │  • Fastify / FastAPI            │
                │  • Voice Memo Ingestion         │
                │  • Priority Extraction Service  │
                └───────────────┬─────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌───────────────────────────────┐       ┌───────────────────────────────┐
│     Agent Orchestration       │       │    Local Desktop Bridge       │
│  • Task Deconstruction        │       │  • Window Tiler               │
│  • Research & Outline Drafter │       │  • Process Killer (Slack/Stm) │
│  • Public Ledger Publisher    │       │  • Browser Active Tab Monitor │
└───────────────────────────────┘       └───────────────────────────────┘
```

### Component Details

### 1. Ingestion Engine (Voice Memo $\to$ Structured Priorities)
- **Input:** 60-second audio stream recorded at night.
- **Processing:** Transcribed via STT (Whisper / Deepgram) and parsed by the LLM into a strict JSON schema:
```json
{
  "date": "YYYY-MM-DD",
  "priorities": [
    {
      "id": "task_1",
      "title": "Finalize Q3 Pitch Deck",
      "verification_type": "url",
      "verification_criteria": "Google Slides URL with 10 slides completed",
      "prep_actions": [
        "Open template in browser",
        "Summarize previous quarterly notes into bullet draft"
      ]
    }
  ]
}
```

### 2. Workspace Stager (The Launchpad)
- Executes an automated script (AppleScript on macOS or PowerShell on Windows) triggered at start-of-day:
  - Terminates or minimizes distracting applications (Steam, Discord, Twitter).
  - Tangles two display zones:
    - **Zone A (Focus):** Target application (IDE, browser doc, writing tool).
    - **Zone B (Agent Sidecar):** Extracted goals, countdown timer, and pre-gathered references.

### 3. Active Monitor (The Mirror)
- Lightweight background process polls active window titles / active browser tabs.
- If domain matches a designated distraction list while in a deep-work session:
  - Injects a system overlay or modal prompt:
    > *"Priority 1 is in progress. Are you blocked on this task, or are you forfeiting today's commitment?"*
  - **Option A (Blocked):** Agent provides a quick breakdown of the next physical step.
  - **Option B (Break):** User explicitly logs a scheduled pause, preventing unconscious doom-scrolling.

### 4. Proof-of-Work Verification (The Public Ledger)
- Triggered at end-of-day deadline (e.g., 5:00 PM / 8:00 PM).
- Prompt collects artifacts: GitHub commit hash, live URL, document link, or screenshot.
- Posts a standardized summary to a webhook-enabled destination (Slack, Discord, or public feed):
```text
[Daily Proof-of-Work Record]
User: Alex
Commitment: Ship alpha auth flow
Status: VERIFIED
Artifact: github.com/org/repo/commit/4a9f12
```

---

## 5. Hackathon Implementation Roadmap

### Milestone 1: The Core Loop (Hours 0–8)
- [ ] Build minimal web UI with audio recorder.
- [ ] Implement transcription and structured JSON extraction for 3 priorities.
- [ ] Implement local runner script (`launch_workspace.sh` / `.ps1`) to launch target URLs and arrange windows.

### Milestone 2: Enforcement & Interrogation (Hours 8–16)
- [ ] Implement simple browser extension or local Python monitor checking active window titles.
- [ ] Trigger modal alert when distraction signatures appear.
- [ ] Integrate interactive triage dialogue for unblocking stuck tasks.

### Milestone 3: Ledger & Demo Script (Hours 16–24)
- [ ] Wire webhook integration to Discord/Slack for end-of-day Pass/Fail reporting.
- [ ] Draft and rehearse a 3-minute pitch emphasizing:
  1. The flaw of punitive blocking.
  2. The cognitive psychology behind frictionless onboarding.
  3. Live end-to-end demo: Audio memo $\to$ Automated setup $\to$ Interruption triage $\to$ Public record.