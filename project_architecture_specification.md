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

## 4. System Architecture & Components (GrokBot Integration)

```
                ┌──────────────────────────────────────────────┐
                │             Client Interfaces                │
                │  • Web Companion / Local Sidecar UI          │
                │  • Audio Recorder (Web Speech / Night Memo)  │
                │  • Metacognitive Interrogation Modal         │
                └──────────────────────┬───────────────────────┘
                                       │
                                       ▼
                ┌──────────────────────────────────────────────┐
                │          Backend & Gateway API               │
                │  • FastAPI / Fastify Gateway                 │
                │  • STT Ingestion (Whisper / Audio Buffer)    │
                │  • Manifest & Telemetry Store                │
                └──────────────────────┬───────────────────────┘
                                       │
        ┌──────────────────────────────┴──────────────────────────────┐
        ▼                                                             ▼
┌──────────────────────────────────────────────┐       ┌──────────────────────────────────────────────┐
│       GrokBot Agentic Engine (xAI / Cursor)  │       │            Local Desktop Bridge              │
│  • Grok API / xai-sdk / Cursor Agent Runtime │       │  • Window Tiler (Zone A Work / Zone B Sidecar)
│  • Launchpad: Goal Decomp & Pre-Drafting     │       │  • Process Distraction Reducer               │
│  • The Mirror: Semantic Drift & Micro-Triage │       │  • Active Window / Tab Observer              │
│  • The Ledger: Autonomous Proof-of-Work Verif│       │  • Webhook Dispatcher (Discord / Slack)      │
└──────────────────────────────────────────────┘       └──────────────────────────────────────────────┘
```

### Component Details & GrokBot Integration Matrix

| Feature Loop | GrokBot Core Role | Underlying Mechanism / API | Behavioral Outcome |
|---|---|---|---|
| **1. The Launchpad** | Autonomous Goal Decomposition & Blank-Page Pre-Drafting | `xai-sdk` / `api.x.ai/v1` structured outputs (`grok-4.6`/`grok-build-0.1`) + Cursor Agent | Eradicates cold-start friction ($B = MAP$); workspaces and draft stubs appear ready-to-edit. |
| **2. The Mirror** | Semantic Drift Evaluation & Real-Time Micro-Triage | Fast-inference context evaluation + interactive conversational reasoning | Replaces blunt blocking with metacognitive awareness; provides immediate unblocking steps. |
| **3. The Public Ledger** | Impartial Proof-of-Work Auditor & Debrief Summarizer | Agentic artifact inspection (git diffs, URLs, test outputs) + webhook generator | Enforces authentic commitment with zero human nagging or emotional shame. |

---

### Detailed Feature Specifications with GrokBot

#### 1. The Launchpad (Morning / Pre-Session Orchestration)
- **Voice Ingestion & Schema Extraction:**
  - The 60-second evening voice memo is transcribed and submitted to GrokBot with a strict Pydantic / JSON schema.
  - Grok decomposes high-level aspirations into concrete, verifiable milestones:
    ```json
    {
      "date": "2026-10-11",
      "priorities": [
        {
          "id": "task_1",
          "title": "Build Auth Middleware & JWT Verification",
          "verification_type": "git_commit_diff",
          "verification_criteria": "PR containing pass tests for auth middleware and JWT decoding",
          "target_files": ["src/middleware/auth.py", "tests/test_auth.py"],
          "prep_actions": [
            "Scaffold test file with boilerplate fixtures",
            "Generate doc summary of required token claims"
          ]
        }
      ],
      "workspace_layout": {
        "zone_a_target": "Cursor / VS Code",
        "zone_b_sidecar": "http://localhost:3000/sidecar",
        "distraction_blacklist": ["youtube.com", "reddit.com", "x.com"]
      }
    }
    ```
- **Autonomous Cold-Start Pre-Computation (The "Blank Page Killer"):**
  - GrokBot runs asynchronously before work starts (or in persistent cloud/local agent environment):
    - Fetches API documentation or repo context.
    - Creates starter scaffolds, stub files, or outlining bullet points so the user begins by *editing* rather than facing an intimidating blank slate.
- **Local Workspace Stager:**
  - Generates a local `launch_manifest.json` executed by the desktop bridge (AppleScript / Shell):
    - Minimizes / suppresses recreational apps.
    - Arranges **Zone A** (IDE/editor containing the staged draft) and **Zone B** (GrokBot Sidecar showing target criteria, countdown timer, and reference notes).

#### 2. The Mirror (In-Flight Metacognitive Interrogation)
- **Active Context Monitoring:**
  - A lightweight local daemon polls active window titles and browser tabs every 3–5 seconds.
- **GrokBot Semantic Drift Classifier:**
  - Instead of brittle static blocklists (which mistakenly block legitimate technical research on YouTube, Reddit, or StackOverflow), the monitor queries Grok:
    - *Prompt Input:* Current Task Title + Acceptance Criteria + Active Window Title / URL.
    - *Evaluation:* Does this active surface plausibly advance the current milestone?
- **Metacognitive Friction Interruption:**
  - If drift is confirmed, a high-priority, non-antagonistic overlay is presented:
    > **"Active Priority: Build Auth Middleware"**
    > *"You've navigated to Reddit. Are you currently stuck on this task, or are you forfeiting today's commitment?"*
- **GrokBot Real-Time Unblocking (Micro-Triage):**
  - **Path A: "I'm Stuck":** GrokBot immediately intervenes directly in the modal/sidecar:
    - Analyzes the current target file or error.
    - Deconstructs the barrier into the *single next physical micro-step* (e.g. *"Don't worry about complete validation yet; write the 3 lines to parse the Bearer header. Here's a starting template:"*).
  - **Path B: "Forfeiting / Taking a Break":** The user confirms an intentional, scheduled break. GrokBot pauses monitoring without punitive harassment, bypassing psychological reactance.

#### 3. The Public Ledger (End-of-Day Objective Verification)
- **Artifact-Based Verification Deadline:**
  - At session close (e.g., 5:00 PM / 8:00 PM), the Ledger requests the user's proof-of-work artifact (Git commit hash, GitHub PR link, live deployment URL, or doc link).
- **GrokBot Autonomous Proof-of-Work Auditor:**
  - GrokBot inspects the submitted artifact against the morning's `verification_criteria`:
    - *Code Artifacts:* GrokBot inspects the git diff, verifies files modified, and evaluates if the code fulfills the stated scope.
    - *URL / Web Artifacts:* GrokBot fetches the destination URL, verifies responsiveness, and cross-checks the requirements.
  - Generates an objective, unvarnished verification report (`VERIFIED`, `PARTIAL`, or `FAILED`).
- **Public Accountability Webhook:**
  - Formats a neutral, Hawthorne-effect-driven record sent to the team Discord/Slack channel:
    ```text
    ═══════════════════════════════════════════════
    [Daily Proof-of-Work Ledger - Code Ada 2026]
    Participant: Alex
    Committed Goal: Build Auth Middleware & JWT Verification
    Status: VERIFIED (Score: 100%)
    Verified Artifact: github.com/user/project/pull/12
    Audit Note: Auth middleware and 4 unit tests confirmed in diff.
    Drift Triage Events: 1 resolved (Stuck -> Unblocked via GrokBot)
    ═══════════════════════════════════════════════
    ```
- **Nightly Closing & Loop Re-Seeding:**
  - Ingests the closing 60-second audio reflection, stores retrospectives, and seeds the prompt state for tomorrow's Launchpad.

---

## 5. Hackathon Implementation Roadmap (Code Ada 2026 - Off the Clock Track)

### Milestone 1: The GrokBot Launchpad Loop (Hours 0–8)
- [ ] Build minimal web companion with audio recording (Web Speech / MediaRecorder).
- [ ] Implement `xai-sdk` / Grok API integration to transform raw transcripts into structured priority manifests.
- [ ] Implement local workstation stager script (`launch_workspace.sh`) for dual-zone layout and app minimization.

### Milestone 2: The Mirror & Real-Time Triage (Hours 8–16)
- [ ] Implement local daemon to capture active window titles / browser URLs.
- [ ] Hook GrokBot semantic classifier to distinguish research from distraction.
- [ ] Build the metacognitive modal dialogue with GrokBot's "Stuck $\to$ Micro-Step" triage generator.

### Milestone 3: The Public Ledger & Presentation Polish (Hours 16–24)
- [ ] Implement GrokBot proof-of-work auditor for GitHub PR/commit validation.
- [ ] Connect webhook dispatch to Discord/Slack for transparent ledger publishing.
- [ ] Prepare 5-minute presentation following Code Ada guidelines:
  1. Highlight the behavioral psychology (Choice Architecture, Hawthorne Effect, Metacognition).
  2. Emphasize how GrokBot / Cursor acts as an autonomous Chief of Staff rather than a punitive blocker.
  3. Live end-to-end demo: Audio memo $\to$ Automated Grok staging $\to$ Drift interception $\to$ Verified public ledger.