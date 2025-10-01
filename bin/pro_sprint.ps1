# pro_sprint.ps1  — utility helpers for the Pro sprint
# Safe, idempotent, no Pro-only runtime requirements.
function Get-RepoRoot {
  param([string]$HintPath = $PSScriptRoot)
  $d = if ($HintPath) { Resolve-Path $HintPath } else { (Get-Location).Path }
  while ($d -and -not (Test-Path (Join-Path $d ".git"))) {
    $parent = Split-Path -Parent $d
    if ($parent -eq $d) { break }
    $d = $parent
  }
  if (-not $d) { throw "Not inside a git repo. cd to your project root." }
  return $d
}
function Use-Science {
  param([string]$Base = (Get-RepoRoot))
  $mod = Join-Path $Base 'bin\science3.ps1'
  if (!(Test-Path $mod)) { throw "Missing $mod" }
  . $mod
  Write-Host "Loaded: $mod"
}
function Sprint-Check {
  [CmdletBinding()]
  param()
  $ok = $true
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (!$git) { $ok = $false; Write-Warning "git not found in PATH" } else { git --version | Out-Host }
  $code = Get-Command code -ErrorAction SilentlyContinue
  if ($code) { Write-Host "VS Code: $(code --version | Select-Object -First 1)" } else { Write-Warning "VS Code not found (optional)" }
  $psrl = Get-Module -ListAvailable PSReadLine
  if (!$psrl) { Write-Warning "PSReadLine not installed (optional)"; $ok=$ok } else { Write-Host "PSReadLine available" }
  try { Use-Science | Out-Null } catch { $ok=$false; Write-Error $_ }
  if ($ok) { Write-Host "Environment looks good." } else { Write-Warning "Fix the warnings above." }
}
function Set-ProMode {
  # Cosmetic/ergonomic upgrades that don’t change pipeline outputs.
  Try { Import-Module PSReadLine -ErrorAction Stop } Catch {}
  if (Get-Module PSReadLine) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key Tab -Function Complete
    Write-Host "PSReadLine predictive suggestions enabled."
  }
  $env:LOGOS_MODE = "pro"
  Write-Host 'LOGOS_MODE=pro (session-only)'
}
function Snapshot-Knowledge {
  param([string]$Base = (Get-RepoRoot))
  Use-Science -Base $Base | Out-Null
  $snap = Save-KnowledgeSnapshot -Base $Base
  if ($snap) { Write-Host "Snapshot -> $snap" } else { Write-Warning "No knowledge.json yet; run Logos-Update first." }
}
function Diff-TagsFromLatest {
  param([string]$Base = (Get-RepoRoot))
  Use-Science -Base $Base | Out-Null
  $latest = Get-LatestSnapshot -Base $Base
  if (-not $latest) { Write-Warning "No snapshots. Run Snapshot-Knowledge first."; return }
  $cur = Join-Path $Base 'logos\knowledge.json'
  if (!(Test-Path $cur)) { Write-Warning "Missing $cur. Run Logos-Update."; return }
  Compute-TagDiff -BaselinePath $latest.FullName -CurrentPath $cur
}
function Export-HitsCsv {
  param(
    [string[]]$Any,
    [string[]]$All,
    [string]$Out = (Join-Path (Get-RepoRoot) ("exports\hits_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".csv"))
  )
  Use-Science | Out-Null
  if ($Out) { $dir = Split-Path -Parent $Out; if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null } }
  Export-Search -Any $Any -All $All -Out $Out
}
function Run-SprintStep {
  <#
    .SYNOPSIS  One command to run common steps.
    .EXAMPLES
      Run-SprintStep doctrine
      Run-SprintStep report -Any near-death,gamma
      Run-SprintStep export  -Any near-death,gamma -All lfp
      Run-SprintStep snapshot
      Run-SprintStep diff
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateSet('doctrine','report','export','snapshot','diff','all')]
    [string]$Step,
    [string[]]$Any,
    [string[]]$All,
    [int]$Top = 50,
    [switch]$Open
  )
  $Base = Get-RepoRoot
  Use-Science -Base $Base | Out-Null
  switch ($Step) {
    'doctrine' {
      Logos-Run -Base $Base
      Logos-Update -Base $Base
    }
    'report' {
      Logos-RunAll -Base $Base -Any $Any -All $All -Top $Top -Open:$Open
    }
    'export' {
      Export-HitsCsv -Any $Any -All $All
    }
    'snapshot' {
      Snapshot-Knowledge -Base $Base
    }
    'diff' {
      Diff-TagsFromLatest -Base $Base | Format-Table -AutoSize
    }
    'all' {
      Set-ProMode
      Logos-RunAll -Base $Base -Any $Any -All $All -Top $Top -Open:$Open
      Snapshot-Knowledge -Base $Base
      Diff-TagsFromLatest -Base $Base | Format-Table -AutoSize
    }
  }
}
function Ensure-Remote {
  param(
    [string]$Name = 'origin',
    [Parameter(Mandatory)][string]$Url
  )
  $rem = git remote -v | Select-String "^\s*$Name\s+$Url\s+\(fetch\)" -ErrorAction SilentlyContinue
  if (-not $rem) {
    git remote remove $Name 2>$null | Out-Null
    git remote add $Name $Url
    Write-Host "Remote '$Name' -> $Url"
  } else {
    Write-Host "Remote '$Name' already set."
  }
}
function Push-Repo {
  param([string]$Branch='main',[string]$Remote='origin')
  git add -A
  git commit -m "chore: sprint sync $(Get-Date -Format s)" 2>$null | Out-Null
  git push $Remote $Branch
}
if ($MyInvocation.MyCommand.Module) { Export-ModuleMember -Function * }


