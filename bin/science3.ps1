function Rebuild-Index {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  $parsed = Join-Path $Base 'parsed'
  $outCsv = Join-Path $Base 'science_index.csv'
  $rows = foreach($f in Get-ChildItem "$parsed\PMC*.txt" -ErrorAction SilentlyContinue){
    $t = Get-Content $f.FullName -Raw
    function Grab($label,$text){ $m=[regex]::Match($text,"(?m)^${label}:\s*(.*)$"); if($m.Success){$m.Groups[1].Value.Trim()} else {""} }
    [pscustomobject]@{
      PMCID   = [IO.Path]::GetFileNameWithoutExtension($f.Name)
      TITLE   = Grab 'TITLE'   $t
      JOURNAL = Grab 'JOURNAL' $t
      DATE    = Grab 'DATE'    $t
      DOI     = Grab 'DOI'     $t
      URL     = Grab 'URL'     $t
    }
  }
  $rows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
  Write-Host "OK index -> $outCsv"
}
function Build-Jsonl {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [string]$OutJsonl = $(Join-Path $Base 'jsonl\pmc_catalog.v2.jsonl')
  )
  $PARSED = Join-Path $Base 'parsed'
  $RAW    = Join-Path $Base 'raw'
  New-Item -ItemType Directory -Force -Path (Split-Path $OutJsonl) | Out-Null
  if (Test-Path $OutJsonl) { Remove-Item $OutJsonl -Force }
  function Grab($label,$text){ $m=[regex]::Match($text,"(?m)^${label}:\s*(.*)$"); if($m.Success){$m.Groups[1].Value.Trim()} else {""} }
  function Sha256OfFile($path){ if(Test-Path $path){ (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower() } else { "" } }
  Get-ChildItem "$PARSED\PMC*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
    $pmcid = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $t     = Get-Content $_.FullName -Raw
    $title    = Grab 'TITLE'   $t
    $journal  = Grab 'JOURNAL' $t
    $date     = Grab 'DATE'    $t
    $doi      = Grab 'DOI'     $t
    $url      = Grab 'URL'     $t
    $authorsL = Grab 'AUTHORS' $t
    $authors  = @(); if ($authorsL) { $authors = $authorsL -split '\s*,\s*' | Where-Object { $_ } }
    $abs  = "";  $mAbs  = [regex]::Match($t, "(?s)(?m)ABSTRACT:\s*(.*?)(?:\r?\n\r?\n|^BODY:)")
    if ($mAbs.Success) { $abs = $mAbs.Groups[1].Value.Trim() }
    $body = "";  $mBody = [regex]::Match($t, "(?s)BODY:\s*(.*)$")
    if ($mBody.Success) { $body = $mBody.Groups[1].Value.Trim() }
    $wc = if ($body) { ($body -split '\s+').Count } else { 0 }
    $rawHtmlPath = Join-Path $RAW "$pmcid.html"
    $sourceHash  = Sha256OfFile $rawHtmlPath
    $nowUtc      = [DateTimeOffset]::UtcNow.ToString("o")
    $rec = [ordered]@{
      schema_version     = "pmc-2.0"
      pmcid              = $pmcid
      title              = $title
      journal            = $journal
      date               = $date
      doi                = $doi
      url                = $url
      authors            = $authors
      abstract           = $abs
      body_text          = $body
      word_count_body    = $wc
      source_hash_sha256 = $sourceHash
      built_at_utc       = $nowUtc
    }
    ($rec | ConvertTo-Json -Depth 6 -Compress) | Out-File -FilePath $OutJsonl -Append -Encoding UTF8
  }
  Write-Host "OK jsonl -> $OutJsonl"
}
function Load-TagRules {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  $tagsPath = Join-Path $Base "tags.json"
  if (!(Test-Path $tagsPath)) { throw "Missing tags.json at $tagsPath" }
  (Get-Content $tagsPath -Raw | ConvertFrom-Json)
}
function Tag-StudiesFromFile {
  param(
    [string]$Base     = "C:\Users\James\OneDrive\Desktop\science",
    [string]$InJsonl  = $(Join-Path $Base 'jsonl\pmc_catalog.v2.jsonl'),
    [string]$OutJsonl = $(Join-Path $Base 'jsonl\pmc_catalog.v3.jsonl')
  )
  if (!(Test-Path $InJsonl)) { throw "Input JSONL not found: $InJsonl" }
  $rules = Load-TagRules -Base $Base
  New-Item -ItemType Directory -Force -Path (Split-Path $OutJsonl) | Out-Null
  if (Test-Path $OutJsonl) { Remove-Item $OutJsonl -Force }
  $i = 0; $tagged = 0
  Get-Content $InJsonl | ForEach-Object {
    $line = $_.Trim(); if (-not $line) { return }
    $rec = $line | ConvertFrom-Json
    $parts = @()
    if ($rec.title)     { $parts += [string]$rec.title }
    if ($rec.abstract)  { $parts += [string]$rec.abstract }
    if ($rec.body_text) { $parts += [string]$rec.body_text }
    $hay = ($parts -join " `n"); if (-not $hay) { $hay = "" }
    $hay = $hay.ToLowerInvariant()
    $tags = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($kv in $rules.PSObject.Properties) {
      $tag = $kv.Name
      foreach ($p in $kv.Value) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ([regex]::IsMatch($hay, $p, 'IgnoreCase')) { $null = $tags.Add($tag); break }
      }
    }
    if ($rec.PSObject.Properties.Match('tags').Count -gt 0 -and $rec.tags) {
      foreach ($t in @($rec.tags)) { if ($t) { $null = $tags.Add([string]$t) } }
    }
    $out = [ordered]@{}
    foreach ($p in $rec.PSObject.Properties) { $out[$p.Name] = $p.Value }
    $out['tags'] = [string[]]$tags
    ($out | ConvertTo-Json -Depth 10 -Compress) | Out-File -FilePath $OutJsonl -Append -Encoding UTF8
    $i++; if ($tags.Count -gt 0) { $tagged++ }
  }
  Write-Host "OK tagged $tagged / $i -> $OutJsonl"
}
function Search-Tags {
  param(
    [string]   $Base = "C:\Users\James\OneDrive\Desktop\science",
    [string[]] $Any,
    [string[]] $All
  )
  $jsonl = Join-Path $Base 'jsonl\pmc_catalog.v3.jsonl'
  if (!(Test-Path $jsonl)) { throw "Missing $jsonl. Run Logos-Run first." }
  $rows = Get-Content $jsonl | ForEach-Object { $_ | ConvertFrom-Json }
  if ($Any -and $Any.Count) {
    $anyLower = $Any | ForEach-Object { $_.ToLower() }
    $rows = $rows | Where-Object {
      $tagsLower = @($_.tags) | ForEach-Object { $_.ToString().ToLower() }
      (($anyLower | Where-Object { $_ -in $tagsLower }).Count -gt 0)
    }
  }
  if ($All -and $All.Count) {
    $allLower = $All | ForEach-Object { $_.ToLower() }
    $rows = $rows | Where-Object {
      $tagsLower = @($_.tags) | ForEach-Object { $_.ToString().ToLower() }
      (($allLower | Where-Object { $_ -notin $tagsLower }).Count -eq 0)
    }
  }
  $rows | Select-Object pmcid, title, journal, url, tags
}
function Add-Insight {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [Parameter(Mandatory)] [string]$Title,
    [Parameter(Mandatory)] [string]$Body,
    [string[]]$Tags = @()
  )
  $insDir  = Join-Path $Base 'insights'
  $insFile = Join-Path $insDir 'insights.jsonl'
  New-Item -ItemType Directory -Force -Path $insDir | Out-Null
  $rec = [ordered]@{
    ts    = [DateTimeOffset]::UtcNow.ToString('o')
    title = $Title
    body  = $Body
    tags  = $Tags
  }
  ($rec | ConvertTo-Json -Compress) | Out-File -FilePath $insFile -Append -Encoding UTF8
  Write-Host "OK insight -> $insFile"
}
function Logos-Update {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  $jsonlV3  = Join-Path $Base 'jsonl\pmc_catalog.v3.jsonl'
  $insFile  = Join-Path $Base 'insights\insights.jsonl'
  $logosDir = Join-Path $Base 'logos'
  $knowledge= Join-Path $logosDir 'knowledge.json'
  $doctrine = Join-Path $logosDir 'doctrine.md'
  New-Item -ItemType Directory -Force -Path $logosDir | Out-Null
  if (!(Test-Path $jsonlV3)) { throw "Missing $jsonlV3. Run Logos-Run first." }
  $rows = Get-Content $jsonlV3 | ForEach-Object { $_ | ConvertFrom-Json }
  $tagFreq = @{}
  foreach($r in $rows){
    if ($r.PSObject.Properties.Match('tags').Count -gt 0 -and $r.tags){
      foreach($t in $r.tags){
        $k = [string]$t
        if($k){ if($tagFreq.ContainsKey($k)){ $tagFreq[$k]++ } else { $tagFreq[$k] = 1 } }
      }
    }
  }
  $insights = @()
  if (Test-Path $insFile) { $insights = Get-Content $insFile | ForEach-Object { $_ | ConvertFrom-Json } }
  $knowledgeObj = [ordered]@{
    built_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    corpus_size  = @($rows).Count
    tags         = $tagFreq.GetEnumerator() | Sort-Object -Property Value -Descending |
                   ForEach-Object { @{ tag = $_.Key; count = $_.Value } }
    insights     = $insights
  }
  $knowledgeObj | ConvertTo-Json -Depth 6 | Out-File -FilePath $knowledge -Encoding UTF8
  $topTags = ( $knowledgeObj.tags | Select-Object -First 10 | ForEach-Object { "- **$($_.tag)**: $($_.count)" } ) -join "`n"
  $insMd   = ( $insights | Select-Object -First 10 | ForEach-Object { "* $($_.ts) - **$($_.title)** - $($_.body)" } ) -join "`n"
$md = @"
# Logos Doctrine
Built: $($knowledgeObj.built_at_utc)
Corpus Size: $($knowledgeObj.corpus_size)
## Top Tags
$topTags
## Recent Insights
$insMd
"@
  $md | Out-File -FilePath $doctrine -Encoding UTF8
  Write-Host "OK Logos updated -> $knowledge"
  Write-Host "OK Doctrine written -> $doctrine"
}
function Logos-Run {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  Write-Host "Rebuilding index..."; Rebuild-Index -Base $Base
  Write-Host "Building JSONL...";  Build-Jsonl    -Base $Base
  Write-Host "Tagging records..."; Tag-StudiesFromFile -Base $Base
  Write-Host "Done."
}
function Update-Tags {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [hashtable]$Add
  )
  $TagsPath = Join-Path $Base "tags.json"
  $tags = if (Test-Path $TagsPath) { Get-Content $TagsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  foreach ($k in $Add.Keys) {
    $existing = @()
    if ($tags.PSObject.Properties.Match($k).Count -gt 0) { $existing = @($tags.$k) | ForEach-Object { [string]$_ } }
    else { Add-Member -InputObject $tags -NotePropertyName $k -NotePropertyValue @() }
    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]([string[]]([string[]]$existing)))
    foreach ($p in $Add[$k]) { if ($p -and -not $set -contains ($p)) { $null = $set.Add($p) } }
    $tags.$k = [string[]]$set
  }
  $tags | ConvertTo-Json -Depth 10 | Out-File -FilePath $TagsPath -Encoding UTF8
  Write-Host "OK tags.json updated -> $TagsPath"
}
function Logos-RunAll {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [string[]]$Any,
    [string[]]$All,
    [int]$Top = 50,
    [switch]$Open
  )
  $addPath = Join-Path $Base "logos\tags_additions.json"
  if (Test-Path $addPath) {
    try {
            # Read additions as array-of-objects and reshape to { tag -> [patterns] }
      $addObj = Get-Content $addPath -Raw | ConvertFrom-Json
      $add = @{}
      foreach ($e in ($addObj | Where-Object { $_ -and $_.tag })) {
        $tag = [string]$e.tag
        if (-not $tag) { continue }
        $pat = @()
        if ($e.PSObject.Properties.Name -contains 'patterns' -and $e.patterns) {
          foreach ($p in $e.patterns) { if ($null -ne $p) { $pat += [string]$p } }
        }
        $pat = $pat | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique | Sort-Object
        $add[$tag] = [string[]]$pat
      }
      if ($add.Count -gt 0) { Update-Tags -Base $Base -Add $add }
    } catch {
      Write-Warning "tags_additions.json parse error: $($_.Exception.Message)"
    }
  }
  Write-Host "Rebuilding index..."; Rebuild-Index -Base $Base
  Write-Host "Building JSONL..." ;  Build-Jsonl    -Base $Base
  Write-Host "Tagging records..." ; Tag-StudiesFromFile -Base $Base
  Logos-Update -Base $Base
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $out   = Join-Path $Base "logos\reports\report_$stamp.md"
  if (-not (Get-Command Generate-Report -ErrorAction SilentlyContinue)) {
$doc = @"
# Logos Report ($stamp)
See: logos\doctrine.md
"@
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    $doc | Set-Content -Path $out -Encoding UTF8
  } else {
    Generate-Report -Base $Base -Any $Any -All $All -Top $Top -OutPath $out
  }
  Write-Host "OK report -> $out"
  if ($Open) {
    $code = Get-Command code -ErrorAction SilentlyContinue
    if ($code) { & $code $out } else { Start-Process notepad.exe $out }
  }
}
function Add-Pattern {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Pattern
  )
  $tagsPath = Join-Path $Base 'logos\tags_additions.json'
  $obj = if (Test-Path $tagsPath) { Get-Content $tagsPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  if ($obj.PSObject.Properties.Match($Tag).Count -eq 0) { Add-Member -InputObject $obj -NotePropertyName $Tag -NotePropertyValue @() }
  $arr = @($obj.$Tag) + @($Pattern)
  $obj.$Tag = $arr | Select-Object -Unique
  $obj | ConvertTo-Json -Depth 10 | Out-File -FilePath $tagsPath -Encoding UTF8
  Write-Host "OK additions updated -> $tagsPath"
}
function ConvertTo-MDTable {
  param([Parameter(Mandatory)][object[]]$Rows,[string[]]$Headers)
  if (-not $Rows -or $Rows.Count -eq 0) { return "" }
  if (-not $Headers -or $Headers.Count -eq 0) { $Headers = $Rows[0].psobject.Properties.Name }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($Headers -join " | "))
  [void]$sb.AppendLine((($Headers | ForEach-Object { "---" }) -join " | "))
  foreach($r in $Rows){
    $vals = foreach($h in $Headers){
      $v = $r.$h
      if ($null -eq $v) { "" }
      elseif ($v -is [System.Array]) { ($v -join ", ") }
      else { [string]$v }
    }
    [void]$sb.AppendLine(($vals -join " | "))
  }
  $sb.ToString().TrimEnd()
}
function Generate-Report {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [string[]]$Any,
    [string[]]$All,
    [int]$Top = 50,
    [string]$OutPath
  )
  $jsonlV3   = Join-Path $Base 'jsonl\pmc_catalog.v3.jsonl'
  $insFile   = Join-Path $Base 'insights\insights.jsonl'
  $logosDir  = Join-Path $Base 'logos'
  $repDir    = Join-Path $logosDir 'reports'
  $knowPath  = Join-Path $logosDir 'knowledge.json'
  if (-not (Test-Path $jsonlV3)) { throw "Missing $jsonlV3. Run Logos-Run first." }
  if ([string]::IsNullOrWhiteSpace($OutPath)) {
    New-Item -ItemType Directory -Force -Path $repDir | Out-Null
    $OutPath = Join-Path $repDir ("report_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".md")
  } else {
    $dir = Split-Path -Parent $OutPath
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  }
  $now      = [DateTimeOffset]::UtcNow.ToString('u')
  $rowsAll  = Get-Content $jsonlV3 | ForEach-Object { $_ | ConvertFrom-Json }
  $rowsHit  = Search-Tags -Base $Base -Any $Any -All $All
  $cooc     = Top-Cooccurrences -Base $Base -Top $Top
  $insights = if (Test-Path $insFile) { Get-Content $insFile | ForEach-Object { $_ | ConvertFrom-Json } } else { @() }
  $knowledge= if (Test-Path $knowPath){ Get-Content $knowPath -Raw | ConvertFrom-Json } else { $null }
$hdr = @"
# Logos Report
Built: $now
Base:  $Base
"@
  $summaryRows = @(
    [pscustomobject]@{ metric = 'Corpus size'; value = @($rowsAll).Count }
    [pscustomobject]@{ metric = 'Filtered hits'; value = @($rowsHit).Count }
    [pscustomobject]@{ metric = 'Top tag count (knowledge)'; value = if($knowledge){ @($knowledge.tags).Count } else { 0 } }
  )
  $summaryMD = ConvertTo-MDTable -Rows $summaryRows -Headers @('metric','value')
  $topTagsMD = ""
  if ($knowledge -and $knowledge.tags) {
    $topTagsMD = ConvertTo-MDTable -Rows ($knowledge.tags | Select-Object -First 25) -Headers @('tag','count')
  }
  $coocRows = $cooc | ForEach-Object {
    $parts = $_.pair -split '\|',2
    [pscustomobject]@{ tagA = $parts[0]; tagB = $parts[1]; count = $_.count }
  }
  $coocMD = ConvertTo-MDTable -Rows ($coocRows | Select-Object -First 25) -Headers @('tagA','tagB','count')
  $hitsMD = ConvertTo-MDTable -Rows (
               $rowsHit | Select-Object -First $Top -Property pmcid,title,journal,url,tags
             ) -Headers @('pmcid','title','journal','url','tags')
  $insRows = $insights |
               Sort-Object { $_.ts } -Descending |
               Select-Object -First 20 -Property ts,title,body,tags
  $insMD = ConvertTo-MDTable -Rows $insRows -Headers @('ts','title','body','tags')
$md = @"
$hdr
## Summary
$summaryMD
## Top Tags
$topTagsMD
## Tag Co-occurrences (Top $Top)
$coocMD
## Filtered Hits (Any: $(@($Any) -join ', ')  All: $(@($All) -join ', '))
$hitsMD
## Recent Insights
$insMD
"@
  $md | Set-Content -Path $OutPath -Encoding UTF8
  Write-Host "OK report -> $OutPath"
}
function Top-Cooccurrences {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [int]$Top = 25
  )
  $j = Join-Path $Base 'jsonl\pmc_catalog.v3.jsonl'
  if (!(Test-Path $j)) { throw "Missing $j. Run Logos-Run first." }
  $pairs = @{}
  Get-Content $j | ForEach-Object {
    $r = $_ | ConvertFrom-Json
    if ($r.tags) {
      $tags = (@($r.tags) | ForEach-Object { $_.ToString().ToLower() } | Sort-Object -Unique)
      for($i=0;$i -lt $tags.Count;$i++){
        for($k=$i+1;$k -lt $tags.Count;$k++){
          $p = "$($tags[$i])|$($tags[$k])"
          if($pairs.ContainsKey($p)){$pairs[$p]++} else {$pairs[$p]=1}
        }
      }
    }
  }
  $pairs.GetEnumerator() |
    Sort-Object -Property Value -Descending |
    Select-Object -First $Top @{n='pair';e={$_.Key}}, @{n='count';e={$_.Value}}
}
function Export-Search {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [string[]]$Any,
    [string[]]$All,
    [string]$Out = $(Join-Path $Base ("exports\export_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".csv")),
    [switch]$Open
  )
  $rows = Search-Tags -Base $Base -Any $Any -All $All
  $outDir = Split-Path -Parent $Out
  if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Out
  Write-Host "OK export -> $Out"
  if ($Open) {
    if (Get-Command code -ErrorAction SilentlyContinue) { code $Out } else { Start-Process $Out }
  }
}
function Search-Text {
  param(
    [string]$Base = "C:\Users\James\OneDrive\Desktop\science",
    [Parameter(Mandatory)][string]$Query,
    [int]$Context = 2,
    [int]$Max = 50
  )
  $parsed = Join-Path $Base 'parsed'
  $hits = Select-String -Path (Join-Path $parsed 'PMC*.txt') -Pattern $Query -SimpleMatch -Context $Context -ErrorAction SilentlyContinue
  $hits | Select-Object -First $Max
}
function Get-LatestSnapshot {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  $hist = Join-Path $Base "logos\history"
  if (-not (Test-Path $hist)) { return $null }
  Get-ChildItem $hist -Filter knowledge_*.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}
function Save-KnowledgeSnapshot {
  param([string]$Base = "C:\Users\James\OneDrive\Desktop\science")
  $know = Join-Path $Base "logos\knowledge.json"
  if (-not (Test-Path $know)) { return $null }
  $hist = Join-Path $Base "logos\history"
  New-Item -ItemType Directory -Force -Path $hist | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $out   = Join-Path $hist "knowledge_$stamp.json"
  Copy-Item $know $out -Force
  return $out
}
function Get-TagListFromKnowledge {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    return @()
  }
  $json = Get-Content $Path -Raw | ConvertFrom-Json
  if ($null -ne $json -and $null -ne $json.tags) {
    $json.tags | ForEach-Object {
      [pscustomobject]@{
        tag   = $_.tag
        count = $_.count
      }
    }
  }
  else {
    @()
  }
}
function Compute-TagDiff {
  param(
    [Parameter(Mandatory)][string]$BaselinePath,
    [Parameter(Mandatory)][string]$CurrentPath
  )
  $base = @{}
  foreach ($t in (Get-TagListFromKnowledge -Path $BaselinePath)) {
    $k = $t.tag.ToString().ToLower()
    $base[$k] = $t.count
  }
  $cur = Get-TagListFromKnowledge -Path $CurrentPath
  $newOnes = foreach ($t in $cur) {
    $k = $t.tag.ToString().ToLower()
    if (-not $base.ContainsKey($k)) {
      [pscustomobject]@{
        tag   = $t.tag
        count = $t.count
      }
    }
  }
  $newOnes | Sort-Object count -Descending
}









