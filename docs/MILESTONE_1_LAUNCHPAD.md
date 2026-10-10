# Implementation Plan: Milestone 1 — The Launchpad
> **Subgroup Alpha Deliverable**  
> **Focus:** Morning Autonomous Workspace Staging & Cold-Start Eliminator ($B = MAP$)

---

## 🎯 Executive Overview & Goal

The Launchpad removes the activation energy required to begin deep work. When a user opens their laptop in the morning:
1. A clean, full-screen curtain takes over the display: *"Good morning. GrokBot is preparing your workspace."*
2. In the background, GrokBot reads last night's carry-over goals, scans target files, and **pre-drafts initial scaffolding/stubs** so the user starts by *editing* rather than confronting an intimidating blank page.
3. A native macOS AppleScript bridge suppresses distractions (Discord, Steam) and tiles the display into **Zone A** (IDE/editor on the left 70%) and **Zone B** (GrokBot Sidecar on the right 30%).
4. The curtain dismisses, presenting the user with an immediately actionable workspace.

---

## 🧩 Architectural Components

```
┌────────────────────────────────────────────────────────┐
│ 1. Wake / Resume Detector (scripts/wake_detector.py)   │
│    • Heartbeat loop detecting timestamp gaps > 30s     │
│    • Calls POST /api/launchpad/trigger                 │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│ 2. Full-Screen Curtain UI (frontend/curtain.html)      │
│    • Launched in borderless / kiosk mode               │
│    • Live progress ticker of GrokBot staging actions   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│ 3. GrokBot Cold-Start Engine (backend/launchpad.py)    │
│    • Reads data/session_state.json (seeded by M3)      │
│    • xai-sdk / Grok prompts for starter scaffolding    │
│    • Writes boilerplate/stubs into target file         │
│    • Generates data/launch_manifest.json               │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│ 4. macOS Window Tiler (scripts/tile_workspace.applescript│
│    • Quits / minimizes recreational apps               │
│    • Positions IDE in Zone A (left 70% width)          │
│    • Positions Sidecar in Zone B (right 30% width)     │
│    • Closes curtain window                             │
└────────────────────────────────────────────────────────┘
```

---

## 📋 Task Breakdown for Subgroup Alpha

### Task 1.1: Wake & Resume Detection Daemon
- **File:** `scripts/wake_detector.py`
- **Functionality:**
  - Maintains a 5-second polling loop checking system clock time.
  - If `(current_time - last_time) > 30 seconds`, the OS was sleeping (lid closed) and has resumed.
  - Fires an HTTP `POST http://localhost:8000/api/launchpad/trigger`.
  - Supports a manual flag `--now` for instant hackathon testing and live demos.

### Task 1.2: Full-Screen Launchpad Curtain View
- **File:** `frontend/curtain.html` & `frontend/static/css/curtain.css`
- **Functionality:**
  - Minimalist, dark-mode, edge-to-edge layout.
  - Headline: *"Good morning Alex. GrokBot is preparing your workspace."*
  - Animated progress ticker consuming Server-Sent Events (SSE) or WebSocket from the backend:
    - `[✓] Ingested morning priority from session state`
    - `[✓] Suppressing recreational distractions`
    - `[✓] Generating starter boilerplate stubs`
    - `[✓] Tiling workspace zones`
  - Closes automatically via `window.close()` or AppleScript when staging completes.

### Task 1.3: GrokBot Cold-Start Scaffolding Engine
- **File:** `backend/services/launchpad_service.py`
- **Functionality:**
  - Ingests `data/session_state.json` (created by Milestone 3).
  - Uses `xai-sdk` (model `grok-4.6` or `grok-build-0.1`) with prompt:
    ```text
    Given priority: "Build Auth Middleware & JWT Verification"
    and acceptance criteria: "Unit tests passing for token verification"
    Scaffold a 20-line starter boilerplate in Python with stub functions and fixtures
    so the developer starts by editing rather than a blank file.
    ```
  - Writes the generated starter stub into the target project file.
  - Emits `data/launch_manifest.json` adhering to the shared schema:
    ```json
    {
      "session_id": "session_2026_10_11",
      "priority_title": "Build Auth Middleware & JWT Verification",
      "target_app": "Cursor",
      "target_file": "/path/to/project/src/auth.py",
      "zone_a": { "left": 0, "top": 0, "width_percent": 70 },
      "zone_b": { "left": 70, "top": 0, "width_percent": 30 },
      "distraction_apps": ["Discord", "Steam"]
    }
    ```

### Task 1.4: macOS AppleScript Window Tiler
- **File:** `scripts/tile_workspace.applescript` (and Python wrapper `backend/services/window_manager.py`)
- **Functionality:**
  - Uses `osascript` to query display bounds via `System Events`.
  - Sends quit/hide signals to applications in `distraction_apps`.
  - Opens target IDE with the target file and sets its window bounds: `[0, 0, screenWidth * 0.70, screenHeight]`.
  - Opens Chrome/Safari to `http://localhost:8000/sidecar.html` and sets bounds: `[screenWidth * 0.70, 0, screenWidth, screenHeight]`.
  - Closes the curtain window.

### Task 1.5: Persistent Zone B GrokBot Sidecar
- **File:** `frontend/sidecar.html` & `frontend/static/js/sidecar.js`
- **Functionality:**
  - Displays:
    1. Active priority title and acceptance criteria.
    2. Deep work countdown timer (e.g., 90-minute block).
    3. Quick unblocking scratchpad linked to GrokBot for fast technical questions.

---

## 🧪 Verification & Demo Checklist

- [ ] **Manual Trigger Test:** Run `python scripts/wake_detector.py --now` and verify backend receives trigger.
- [ ] **Curtain Launch Test:** Curtain opens full-screen and displays live ticker updates.
- [ ] **GrokBot Pre-Draft Test:** Check that target stub file is created/updated with sensible boilerplate code from Grok.
- [ ] **Window Tiling Test:** On macOS, Cursor/VS Code snaps to left 70% and Sidecar snaps to right 30%.
- [ ] **Distraction Test:** Open Discord, trigger Launchpad, verify Discord is minimized or hidden.
