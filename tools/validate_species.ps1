# Validates each NDJSON line in species.json for JSON syntax
# and reports simple data anomalies (placeholder weights, odd rarity keys)

$ErrorActionPreference = 'Stop'

$speciesFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..' | Join-Path -ChildPath 'species.json'
if (-not (Test-Path -LiteralPath $speciesFile)) {
    Write-Error "species.json not found at $speciesFile"
    exit 1
}

Write-Host "Validating: $speciesFile" -ForegroundColor Cyan

$lineNumber = 0
$parseErrors = @()
$anomalies = @()
$total = 0

Get-Content -LiteralPath $speciesFile | ForEach-Object {
    $line = $_
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    $total++
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        # Basic anomaly checks
        if ($null -eq $obj.maxWeight -or $obj.maxWeight -eq '' -or $obj.maxWeight -eq 'NA') {
            $anomalies += [PSCustomObject]@{ Type='MissingMaxWeight'; Line=$lineNumber; Animal=$obj.animal; Value=$obj.maxWeight }
        }
        if ($obj.PSObject.Properties.Name -notcontains 'needZones') {
            $anomalies += [PSCustomObject]@{ Type='MissingNeedZones'; Line=$lineNumber; Animal=$obj.animal; Value='' }
        }
        if ($obj.rarity) {
            $rarityKeys = $obj.rarity.PSObject.Properties.Name
            foreach ($rk in $rarityKeys) {
                if ($rk -match '\\(' -or $rk -match '\\)' -or $rk -match '\\/' -or $rk -match '\\s+$') {
                    $val = ($obj.rarity | Select-Object -ExpandProperty $rk)
                    $anomalies += [PSCustomObject]@{ Type='OddRarityKey'; Line=$lineNumber; Animal=$obj.animal; Value="$rk -> $val" }
                }
            }
        } else {
            $anomalies += [PSCustomObject]@{ Type='MissingRarity'; Line=$lineNumber; Animal=$obj.animal; Value='' }
        }
    }
    catch {
        $parseErrors += [PSCustomObject]@{ Line=$lineNumber; Error=$_.Exception.Message; Raw=$line }
    }
}

if ($parseErrors.Count -eq 0) {
    Write-Host "Syntax: OK ($total JSON objects parsed)" -ForegroundColor Green
} else {
    Write-Host "Syntax: FAILED ($($parseErrors.Count) errors)" -ForegroundColor Red
    $parseErrors | Format-Table -AutoSize | Out-String | Write-Output
}

if ($anomalies.Count -gt 0) {
    Write-Host "Anomalies detected: $($anomalies.Count)" -ForegroundColor Yellow
    $anomalies | Sort-Object Type,Animal | Format-Table -AutoSize | Out-String | Write-Output
} else {
    Write-Host "No data anomalies detected by basic heuristics." -ForegroundColor Green
}
