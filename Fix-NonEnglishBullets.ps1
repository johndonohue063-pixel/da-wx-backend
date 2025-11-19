Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "Scanning Dart files under $AppPath for bad bullet characters..." -ForegroundColor Cyan

if (-not (Test-Path $AppPath)) {
    Write-Host "App path does not exist. Exiting." -ForegroundColor Red
    exit 1
}

# These are the junk sequences we saw in your screenshots
$badToGoodMap = @{
    "â€¢" = "•";                     # generic bullet fix
    "â€“" = "-";                     # en dash glitch
}

$dartFiles = Get-ChildItem -Path $AppPath -Recurse -Include *.dart

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)

    $needsChange = $false
    foreach ($bad in $badToGoodMap.Keys) {
        if ($text.Contains($bad)) {
            $needsChange = $true
            break
        }
    }

    if (-not $needsChange) { continue }

    $backup = "$path.bak_bullets_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $path $backup -Force

    foreach ($bad in $badToGoodMap.Keys) {
        $good = $badToGoodMap[$bad]
        $text = $text.Replace($bad, $good)
    }

    [System.IO.File]::WriteAllText($path, $text)
    Write-Host "Fixed bullet/text encoding in: $path (backup: $backup)" -ForegroundColor Green
}

Write-Host "Done fixing non-English bullet characters." -ForegroundColor Cyan
