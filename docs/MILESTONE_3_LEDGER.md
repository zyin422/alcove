# Implementation Plan: Milestone 3 — The Public Ledger
> **Subgroup Beta Deliverable**  
> **Focus:** End-of-Day 60s Voice Memo, Priority Reconciliation & Webhook Publisher (Hawthorne Effect)

---

## 🎯 Executive Overview & Goal

The Public Ledger enforces authentic accountability through objective proof-of-work and transparent public reporting:
1. At the end of the work session, the user opens the Ledger interface, views the day's commitments, and records a **60-second voice memo**.
2. The user articulates what was completed, what was not, and what roadblocks they hit.
3. GrokBot transcribes the audio, performs structured reconciliation against the morning's goals, and validates any submitted proof-of-work artifacts (GitHub PR diff, commit, or live URL).
4. GrokBot posts an unvarnished audit summary to the shared Discord/Slack channel via webhook.
5. Uncompleted tasks and new priorities are persisted to `data/session_state.json` to immediately seed tomorrow's Launchpad (Milestone 1).

---

## 🧩 Architectural Components

```
┌────────────────────────────────────────────────────────┐
│ 1. Voice Memo Recorder UI (frontend/ledger.html)       │
│    • 60-second audio recorder with live visualizer      │
│    • Today's morning priority checklist display        │
│    • Optional artifact link input (GitHub PR / commit) │
└───────────────────────────┬────────────────────────────┘
                            │ Audio Blob (WAV/WebM)
                            ▼
┌────────────────────────────────────────────────────────┐
│ 2. STT & GrokBot Priority Reconciler (backend)         │
│    • Transcribes speech (Whisper / Deepgram)           │
│    • GrokBot maps spoken status to morning priorities   │
│    • Identifies completed, dropped, and carryover items│
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│ 3. Artifact Auditor Engine (artifact_auditor.py)       │
│    • Inspects GitHub PR diffs or URL response content  │
│    • Computes objective status: VERIFIED / FAILED      │
└───────────────────────────┬────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│ 4. Discord/Slack Webhook  │   │ 5. Session Seed Persistence
│    • Posts public record  │   │    • Writes session_state │
│    • Zero emotional shame │   │    • Seeds M1 Launchpad   │
└───────────────────────────┘   └───────────────────────────┘
```

---

## 📋 Task Breakdown for Subgroup Beta

### Task 3.1: 60-Second Voice Memo Recorder UI
- **File:** `frontend/ledger.html` & `frontend/static/js/audio_recorder.js`
- **Functionality:**
  - Modern audio capture interface using `navigator.mediaDevices.getUserMedia` and `MediaRecorder`.
  - Strict 60-second circular countdown timer with pulsating record indicator.
  - Live audio visualizer (Canvas waveform via Web Audio API `AnalyserNode`).
  - Playback preview and "Submit Debrief" action.
  - Input field for optional proof artifact: `GitHub PR / Commit URL / Live Link`.

### Task 3.2: Audio Transcription & GrokBot Reconciliation Service
- **File:** `backend/services/ledger_service.py`
- **Functionality:**
  - Receives uploaded audio blob at `POST /api/ledger/submit-memo`.
  - Transcribes audio to text (Whisper API or local lightweight STT).
  - Prompts GrokBot (`grok-4.6` via `xai-sdk`) with structured Pydantic schema:
    ```text
    Morning Priorities:
    - [task_1]: "Build Auth Middleware & JWT Verification" (Verification: Pass unit tests)
    - [task_2]: "Database Migration Script" (Verification: Alembic migration file)

    User Voice Memo Transcript:
    "Hey, I was able to get the auth middleware working and tests pass.
    Didn't get to the database migration because Docker broke mid-day."

    Task: Reconcile each priority. Output JSON with status (COMPLETED / INCOMPLETE / BLOCKED),
    extracted blocker summary, and next-day carryover items.
    ```
  - Outputs structured reconciliation object.

### Task 3.3: Proof-of-Work Artifact Auditor
- **File:** `backend/services/artifact_auditor.py`
- **Functionality:**
  - If a GitHub PR/commit URL is provided:
    - Fetches the raw diff or commit metadata via GitHub REST API.
    - Uses GrokBot to audit whether the diff actually satisfies the acceptance criteria (preventing gaming of the system).
  - Assigns an audit status: `VERIFIED`, `PARTIAL_PROOF`, or `UNVERIFIED`.

### Task 3.4: Discord / Slack Webhook Publisher
- **File:** `backend/services/webhook_dispatcher.py`
- **Functionality:**
  - Formats an unvarnished, professional Markdown embed:
    ```text
    ════════════════════════════════════════════════════════
    📢 [DAILY PROOF-OF-WORK AUDIT]
    Builder: Alex
    Session Date: 2026-10-10
    ────────────────────────────────────────────────────────
    ✅ COMPLETED:
       • Build Auth Middleware & JWT Verification
         [Artifact Verified]: github.com/user/repo/pull/14
    ❌ INCOMPLETE:
       • Database Migration Script
         [Reported Blocker]: Docker daemon failure mid-afternoon
    ────────────────────────────────────────────────────────
    📌 Seeded for Tomorrow's Launchpad:
       • Fix Docker environment & run Alembic migration
    ════════════════════════════════════════════════════════
    ```
  - Sends HTTP POST to configured webhook URL (`DISCORD_WEBHOOK_URL`).

### Task 3.5: Next-Day Seed State Generator
- **File:** Updates `data/session_state.json`
- **Functionality:**
  - Saves the verified carry-over priorities to disk.
  - This file serves as the exact starting contract consumed by Subgroup Alpha's Launchpad (Milestone 1) when the laptop opens tomorrow.

---

## 🧪 Verification & Demo Checklist

- [ ] **Audio Capture Test:** Record 10-second test audio in `ledger.html`, confirm audio plays back and waveform animates.
- [ ] **Transcription & Reconciliation Test:** Submit audio saying "Finished task 1, didn't do task 2", verify GrokBot outputs accurate JSON mapping.
- [ ] **Artifact Auditor Test:** Pass a mock GitHub commit link, verify auditor inspects diff against criteria.
- [ ] **Webhook Test:** Trigger webhook dispatch and verify formatted embed renders cleanly in Discord/Slack.
- [ ] **State Handoff Test:** Confirm `data/session_state.json` is updated with tomorrow's priority seed.
