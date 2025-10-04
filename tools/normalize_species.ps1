$src = 'c:\Users\Phoenix\QuickDiamonds\species.json'
$bak = 'c:\Users\Phoenix\QuickDiamonds\species.json.bak'
$default = @{Feeding=@('-','-'); Drinking=@('-'); Resting=@('-')}

if (-not (Test-Path $bak)) { Copy-Item -Path $src -Destination $bak }

$txt = Get-Content -Raw -Path $src -Encoding UTF8
$n = $txt.Length
$idx = 0
$objs = @()
while ($idx -lt $n) {
    $start = $txt.IndexOf('{', $idx)
    if ($start -eq -1) { break }
    $depth = 0
    $i = $start
    while ($i -lt $n) {
        $ch = $txt[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth-- ; if ($depth -eq 0) { $objs += $txt.Substring($start, $i - $start + 1); $idx = $i + 1; break } }
        $i++
    }
    if ($i -ge $n) { break }
}

$parsed = @()
$errors = @()
foreach ($k in 0..($objs.Count-1)) {
    $s = $objs[$k]
    try {
        $o = ConvertFrom-Json $s -ErrorAction Stop
        $parsed += $o
    } catch {
        $errors += @{index=($k+1); msg=$_.Exception.Message; sample=$s.Substring(0, [Math]::Min(200, $s.Length))}
    }
}

$result = @()
foreach ($obj in $parsed) {
    # Collect property names if object
    $keys = @()
    if ($obj -is [System.Management.Automation.PSCustomObject]) { $keys = $obj.PSObject.Properties.Name }
    $kset = $keys | Sort-Object
    # detect needZones-only objects (exact keys Feeding/Drinking/Resting)
    $isNeedZonesOnly = ($kset.Count -eq 3 -and ($kset -contains 'Feeding') -and ($kset -contains 'Drinking') -and ($kset -contains 'Resting'))

    if ($isNeedZonesOnly) {
        if ($result.Count -gt 0) {
            # attach to previous species object if it doesn't already have needZones
            $prev = $result[-1]
            if (-not ($prev.PSObject.Properties.Name -contains 'needZones')) {
                $prev | Add-Member -NotePropertyName needZones -NotePropertyValue $obj -Force
            }
        } else {
            # no previous species; ignore this standalone needZones
        }
        continue
    }

    # normal species object: keep it; we'll ensure needZones exists later
    $result += $obj
}

# ensure every species has needZones; if missing, add default
foreach ($o in $result) {
    if (-not ($o.PSObject.Properties.Name -contains 'needZones')) {
        $o | Add-Member -NotePropertyName needZones -NotePropertyValue $default -Force
    }
}

# write NDJSON single-line
$lines = @()
foreach ($o in $result) {
    $json = $o | ConvertTo-Json -Compress -Depth 10
    $lines += $json
}
Set-Content -Path $src -Value ($lines -join "`n") -Encoding UTF8

Write-Output "NORMALIZE_DONE"
Write-Output "TOTAL_PARSED: $($parsed.Count)"
Write-Output "TOTAL_WRITTEN: $($lines.Count)"
Write-Output "PARSE_ERRORS: $($errors.Count)"
if ($errors.Count -gt 0) { $errors[0..([Math]::Min(4,$errors.Count-1))] | ForEach-Object { Write-Output ("ERR {0} {1}" -f $_.index, $_.msg) } }
