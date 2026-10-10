# Stub for later. macOS is the demo target.
param(
  [string]$FocusUrl = "https://github.com",
  [string]$SidecarUrl = "http://localhost:5173/launch/sidecar"
)
Start-Process $FocusUrl
Start-Process $SidecarUrl
Write-Host "Opened focus + sidecar. Window tiling not implemented on Windows yet."
