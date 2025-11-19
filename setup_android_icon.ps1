# setup_android_icon.ps1
param(
  [string]$BackgroundColor = '#000000',
  [string]$ForegroundPng   = 'assets/images/logo.png'
)

function Ensure-Dir($Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force $Path | Out-Null }
}
function Write-Text($Path, [string]$Content) {
  Ensure-Dir (Split-Path $Path)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
  Write-Host "Wrote $Path" -ForegroundColor Green
}

$root    = Get-Location
$resRoot = Join-Path $root "android\app\src\main\res"

# colors for adaptive icon background
$values = Join-Path $resRoot "values"
Ensure-Dir $values
$colorsXmlPath = Join-Path $values "colors.xml"
if (Test-Path $colorsXmlPath) {
  $c = Get-Content $colorsXmlPath -Raw
  if ($c -notmatch 'ic_launcher_bg') {
    $c = $c -replace '</resources>', "    <color name=""ic_launcher_bg"">$BackgroundColor</color>`n</resources>"
    [System.IO.File]::WriteAllText($colorsXmlPath, $c, (New-Object System.Text.UTF8Encoding($false)))
  }
} else {
  Write-Text $colorsXmlPath @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_bg">$BackgroundColor</color>
</resources>
"@
}

# copy foreground image
$drawable = Join-Path $resRoot "drawable"
Ensure-Dir $drawable
$destPng = Join-Path $drawable "ic_logo_foreground.png"
if (Test-Path $ForegroundPng) {
  Copy-Item $ForegroundPng $destPng -Force
  Write-Host "Copied foreground image to $destPng" -ForegroundColor Green
} else {
  Write-Host "WARN, foreground image not found at $ForegroundPng" -ForegroundColor Yellow
}

# adaptive icon xml
$mipmap = Join-Path $resRoot "mipmap-anydpi-v26"
Ensure-Dir $mipmap
$iconXml = @"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_bg"/>
    <foreground android:drawable="@drawable/ic_logo_foreground"/>
</adaptive-icon>
"@
Write-Text (Join-Path $mipmap "ic_launcher.xml")       $iconXml
Write-Text (Join-Path $mipmap "ic_launcher_round.xml") $iconXml

# ensure manifest uses ic_launcher
$manifest = Join-Path $root "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
  $m = Get-Content $manifest -Raw
  if ($m -notmatch 'android:icon="@mipmap/ic_launcher"') {
    $m = $m -replace 'android:icon="[^"]*"', 'android:icon="@mipmap/ic_launcher"'
    [System.IO.File]::WriteAllText($manifest, $m, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Updated application icon in AndroidManifest.xml" -ForegroundColor Green
  } else {
    Write-Host "Manifest already points to @mipmap/ic_launcher" -ForegroundColor DarkGray
  }
} else {
  Write-Host "WARN, AndroidManifest.xml not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done, launcher icon configured, black tile background with your logo foreground." -ForegroundColor Cyan
