<#
 sanitize_variants.ps1
 Purpose: Clean and normalize the rarity (variant) keys in species.json.
 Actions:
  - Attempts to parse each NDJSON line.
  - Repairs certain malformed rarity sections (removes stray :null fragments, broken tokens).
  - Normalizes variant keys (camelCase -> spaced, trims fragments like "(" or "( ~", strips percent commentary, collapses whitespace).
  - Removes keys that become empty after cleaning or whose value is null.
  - Merges duplicate keys, keeping the LOWEST (rarest) numeric value.
  - Leaves Variation identifiers (e.g., "Piebald Variation 1") intact.
  - Writes cleaned file to species.cleaned.json then replaces original (backup to species.json.preSanitize.bak).
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$speciesFile = Join-Path $root '..' | Join-Path -ChildPath 'species.json'
if (-not (Test-Path -LiteralPath $speciesFile)) { Write-Error "species.json not found"; exit 1 }

$backup = Join-Path $root '..' | Join-Path -ChildPath 'species.json.preSanitize.bak'
$dest   = Join-Path $root '..' | Join-Path -ChildPath 'species.cleaned.json'

Write-Host "Sanitizing variants in: $speciesFile" -ForegroundColor Cyan
if (-not (Test-Path $backup)) { Copy-Item -LiteralPath $speciesFile -Destination $backup -Force }

$culture = [System.Globalization.CultureInfo]::InvariantCulture

function Normalize-Key {
  param([string]$k)
  if (-not $k) { return $null }
  $orig = $k
  $k = $k -replace '^["\s]+','' -replace '["\s]+$',''
  # Remove obvious broken fragments like trailing :null or embedded percent commentary in key
  $k = $k -replace ':?\s*null',''
  # Insert space between lower->Upper boundaries (camelCase) (avoid if already contains 'Variation')
  if ($k -notmatch 'Variation') { $k = [regex]::Replace($k,'([a-z])([A-Z])','$1 $2') }
  # Replace underscores with space
  $k = $k -replace '_',' '
  # Trim fragments starting with ' (', '( ~', '( %', or hanging '('
  $k = $k -replace ' \(.*$',''
  $k = $k -replace '\s+~$',''
  # Remove percent annotations inside key (e.g., 'Piebald 0.5% / 0.3%')
  $k = $k -replace '\d+\.?\d*%',''
  # Collapse multiple spaces
  $k = $k -replace '\s{2,}',' '
  $k = $k.Trim()
  # Specific camel-case tokens to spaced form
  $k = $k -replace 'LightBrown','Light Brown'
  $k = $k -replace 'DarkBrown','Dark Brown'
  $k = $k -replace 'LightGrey','Light Grey'
  $k = $k -replace 'DarkGrey','Dark Grey'
  $k = $k -replace 'GrayBrown','Gray Brown'
  $k = $k -replace 'GreyBrown','Grey Brown'
  $k = $k -replace 'RedBrown','Red Brown'
  $k = $k -replace 'Blackgold','Black Gold'
  $k = $k -replace 'Blackgold','Black Gold'
  $k = $k -replace 'Gingersplit','Ginger Split'
  $k = $k -replace 'Eggwhite','Egg White'
  $k = $k -replace 'MelanisticCC','Melanistic CC'
  # Remove stray leading/trailing punctuation again
  $k = $k -replace '^[,:;]+','' -replace '[,:;]+$',''
  if ($k.Length -eq 0) { return $null }
  return $k
}

[int]$total=0
[int]$parsed=0
[int]$fixed=0
[int]$parseFails=0
$problemLines=@()
$outLines = New-Object System.Collections.Generic.List[string]

Get-Content -LiteralPath $speciesFile | ForEach-Object {
  $line = $_
  $total++
  if ([string]::IsNullOrWhiteSpace($line)) { return }
  $json = $null
  $attempt = $line
  $repairApplied = $false
  try {
    $json = $attempt | ConvertFrom-Json -ErrorAction Stop
  } catch {
    # Attempt simple textual repairs on rarity section
    $repairApplied = $true
    $attempt = $attempt -replace '"\s+"','"' # remove accidental empty key quotes
    $attempt = $attempt -replace ':null,',','
    $attempt = $attempt -replace ':null',''  # trailing
    $attempt = $attempt -replace ',\s*,',',' # double commas
    $attempt = $attempt -replace '"\s*,',', '
    try { $json = $attempt | ConvertFrom-Json -ErrorAction Stop } catch { }
  }
  if (-not $json) {
    $parseFails++
    $problemLines += "Unparsed line $total"
    # Keep original line to avoid data loss
    $outLines.Add($line)
    return
  }
  $parsed++
  if ($json.PSObject.Properties.Name -contains 'rarity') {
    $rarObj = $json.rarity
    $newRarity = @{}
    foreach ($prop in $rarObj.PSObject.Properties) {
      $k = $prop.Name
      $v = $prop.Value
      if ($null -eq $v -or ($v -is [string] -and [string]::IsNullOrWhiteSpace($v))) { continue }
      if ($v -is [string]) { if ($v -match '^[0-9]+(\.[0-9]+)?$') { $v = [double]::Parse($v,$culture) } else { continue } }
      $clean = Normalize-Key -k $k
      if (-not $clean) { continue }
      if ($newRarity.ContainsKey($clean)) {
        # Keep the lower value (rarest)
        if ($v -lt $newRarity[$clean]) { $newRarity[$clean] = $v }
      } else {
        $newRarity[$clean] = $v
      }
    }
    # Sort rarity by ascending value (rarest first) for deterministic output
    $ordered = $newRarity.GetEnumerator() | Sort-Object Value, Name
    # Rebuild JSON line manually to preserve property ordering
    $rarityParts = $ordered | ForEach-Object { '"{0}":{1}' -f $_.Key, ([string]::Format($culture,'{0}', $_.Value)) }
    # Compose
    $builder = '{'
    $fields = @()
    foreach ($name in 'class','animal','maxDifficulty','diamond','basis','maxWeight') {
      if ($json.PSObject.Properties.Name -contains $name) {
        $val = $json.$name
        if ($val -is [string]) { $fields += ('"{0}":{1}' -f $name, ('"' + ($val.Replace('"','\"')) + '"')) } else { $fields += ('"{0}":{1}' -f $name, ([string]::Format($culture,'{0}', $val))) }
      }
    }
    $fields += '"rarity":{' + ($rarityParts -join ',') + '}'
    if ($json.PSObject.Properties.Name -contains 'maps') {
      $mapsJson = ($json.maps | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }) -join ','
      $fields += '"maps":[' + $mapsJson + ']'
    }
    if ($json.PSObject.Properties.Name -contains 'needZones') {
      $nz = $json.needZones
      $zones=@()
      foreach ($zone in 'Feeding','Drinking','Resting') {
        if ($nz.PSObject.Properties.Name -contains $zone) {
          $vals = $nz.$zone | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }
          $zones += '"' + $zone + '":[' + ($vals -join ',') + ']'
        }
      }
      $fields += '"needZones":{' + ($zones -join ',') + '}'
    }
    $builder += ($fields -join ',') + '}'
    $outLines.Add($builder)
    if ($repairApplied -or $ordered.Count -ne $rarObj.PSObject.Properties.Count) { $fixed++ }
  } else {
    $outLines.Add($attempt)
  }
}

$outLines | Set-Content -LiteralPath $dest -Encoding UTF8
Move-Item -LiteralPath $dest -Destination $speciesFile -Force

Write-Host "Total lines: $total" -ForegroundColor Cyan
Write-Host "Parsed: $parsed  ParseFails: $parseFails  LinesFixed: $fixed" -ForegroundColor Cyan
if ($parseFails -gt 0) { Write-Warning "Some lines could not be parsed and were left unchanged (see backup)." }
Write-Host "Backup: $backup" -ForegroundColor Yellow
Write-Host "Done." -ForegroundColor Green
