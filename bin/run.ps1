param([Parameter(ValueFromRemainingArguments=$true)][string[]]$ArgsRemaining)
$Base   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path $Base)) { $Base = "C:\Users\James\OneDrive\Desktop\science" }
$LogDir = Join-Path $Base 'logs'; $Parsed = Join-Path $Base 'parsed'; $Log = Join-Path $LogDir 'pmc_pull.log'; $CtxLog = Join-Path $LogDir 'context.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Context = ($ArgsRemaining -join ' ').Trim()
if ($Context) { Add-Content -Path $CtxLog -Encoding UTF8 -Value ("{0:o} {1}" -f [DateTimeOffset]::UtcNow, $Context); Write-Host "📝 noted: $Context" }
if (Test-Path $Log) { Write-Host "?? Last 8 log lines:"; Get-Content $Log -Tail 8 } else { Write-Host "⚠️  No pmc_pull.log yet at $Log" }
$latest = Get-ChildItem (Join-Path $Parsed 'PMC*.txt') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) { Write-Host "?? Latest parsed: $($latest.FullName)"; Get-Content $latest.FullName -TotalCount 12 } else { Write-Host "⚠️  No parsed articles found in $Parsed" }
