Param(
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance"
)

Write-Host "=== FIX NATIONAL ROUTE START ===" -ForegroundColor Cyan

Set-Location $AppPath

# Find all Dart files that contain 'report/national2'
$dartFiles = Get-ChildItem -Path $AppPath -Recurse -Include *.dart
$target = "report/national2"
$replacement = "report/national"

foreach ($file in $dartFiles) {
    $path = $file.FullName
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains($target)) {
        $backup = "$path.bak_NATIONAL2_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $path $backup -Force
        Write-Host "Backup created: $backup" -ForegroundColor Yellow

        $newText = $text.Replace($target, $replacement)
        [System.IO.File]::WriteAllText($path, $newText)
        Write-Host "Replaced 'report/national2' with 'report/national' in $path" -ForegroundColor Green
    }
}

Write-Host "=== FIX NATIONAL ROUTE DONE ===" -ForegroundColor Cyan
