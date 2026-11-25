# Finish & Demo Checklist

Run from a Mac with Xcode 16.3+, XcodeGen (`brew install xcodegen`) and Google Chrome.

## 1. Finish the merge (one-time)

Merge the last branch:

```bash
cd /Users/axion66/coding/alcove && git merge --no-edit worktree-wf_23a89029-2f2-4
```

Only if `project.pbxproj` conflicts (both branches regenerated it; regenerating fixes it):

```bash
cd /Users/axion66/coding/alcove/Alcove && xcodegen generate && git add Alcove.xcodeproj && git commit --no-edit
```

## 2. Test

Must end with `** TEST SUCCEEDED **`:

```bash
cd /Users/axion66/coding/alcove/Alcove && xcodegen generate && xcodebuild -project Alcove.xcodeproj -scheme Alcove -destination 'platform=macOS' -derivedDataPath build/DerivedData test 2>&1 | grep -E "Executed [0-9]+ tests.*seconds$|TEST (SUCCEEDED|FAILED)" | tail -2
```

## 3. Push

```bash
cd /Users/axion66/coding/alcove && git push origin main
```

## 4. Build & launch

```bash
cd /Users/axion66/coding/alcove/Alcove && xcodebuild -project Alcove.xcodeproj -scheme Alcove -derivedDataPath build/DerivedData build | tail -1 && open build/DerivedData/Build/Products/Debug/Alcove.app
```

## 5. Demo checklist (~15 min)

- [ ] **Settings (⌘,)**
  - [ ] Enter your name and check Discord is on.
  - [ ] **Test connection** shows "Connected as acountabilibrosis · 1 servers".
  - [ ] If a Keychain prompt appears, click **Always Allow**.
- [ ] **"+" → add CS128:** Left/Right layout, 2 sites. While developing, add Terminal and Xcode to the allowed apps.
- [ ] **LOCK IN → Open-ended**
  - [ ] Allow the Chrome control prompt (first time only).
  - [ ] Other apps hide.
  - [ ] Two Chrome windows tile left and right.
  - [ ] The mini timer appears at the top center.
  - [ ] Discord `#general` gets the 🔒 message.
- [ ] **Open Notes or Discord:** it hides right away and a toast appears top-right.
- [ ] **Open youtube.com in Chrome:** the tab closes and a toast appears.
- [ ] **Mini timer ✕**
  - [ ] "End this session?" appears; confirm it.
  - [ ] Hidden apps come back.
  - [ ] The summary sheet shows.
  - [ ] Discord gets ✅.
- [ ] **Custom 1 min:** the session ends on its own after 60 s and Discord gets ✅.
- [ ] **Custom 25 min → ✕:** you must type `I give up on CS128` to end it, and Discord gets 🏳️.
- [ ] **Thirds layout:** the app takes the left third with the giant timer.
- [ ] **Settings → Load demo data:** the Stats day/week/month charts fill in.

## Troubleshooting

If you denied Chrome control, reset it and lock in again:

```bash
tccutil reset AppleEvents com.alcove.app
```
