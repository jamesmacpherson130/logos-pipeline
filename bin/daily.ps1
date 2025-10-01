param(
  [string[]]$Any    = @("near-death","gamma"),
  [string[]]$All    = @(),
  [int]$Top         = 50,
  [switch]$Push,
  [string]$Remote   = "origin",
  [string]$Branch   = "main",
  [string]$RemoteUrl
)
$ErrorActionPreference = "Stop"
# cd to repo root so relative paths work
Set-Location (Split-Path -Parent $PSScriptRoot)   # $PSScriptRoot = ...\bin
# Load the pipeline
$mod = Join-Path $PSScriptRoot "science3.ps1"
if (!(Test-Path $mod)) { throw "Missing $mod" }
. $mod
# Run end-to-end (no window pop) and snapshot
Logos-RunAll -Base (Get-Location).Path -Any $Any -All $All -Top $Top -Open:$false
$null = Save-KnowledgeSnapshot -Base (Get-Location).Path
# Optional auto-push
if ($Push) {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { Write-Warning "git not found in PATH; skipping push."; return }
  # Ensure remote if given
  if ($RemoteUrl) {
    $has = (git remote get-url $Remote 2>$null)
    if (-not $has) {
      git remote add $Remote $RemoteUrl
      Write-Host "Remote '$Remote' -> $RemoteUrl"
    }
  }
  # Make sure we have some remote at all
  try { $null = git remote get-url $Remote 2>$null } catch { 
    Write-Warning "No remote '$Remote' configured and no -RemoteUrl provided; skipping push."
    return
  }
  # Optional: be nice and enable credential manager if not set (prompts once, then caches)
  try {
    if (-not (git config --global credential.helper)) {
      git config --global credential.helper manager-core
    }
  } catch {}
  git add -A
  git commit -m ("daily: auto snapshot " + (Get-Date -Format s)) 2>$null | Out-Null
  git push $Remote $Branch
  Write-Host "Pushed changes to $Remote/$Branch."
}
