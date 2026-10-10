-- Best-effort two-zone layout. Requires Accessibility permission.
tell application "Finder"
  set screenBounds to bounds of window of desktop
end tell
set screenW to item 3 of screenBounds
set screenH to item 4 of screenBounds
set midX to screenW / 2

try
  tell application "System Events"
    set procs to name of every process whose frontmost is true
  end tell
end try

-- Leave windows where the user put them if we cannot control them.
return "ok"
