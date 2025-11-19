# setup_android_splash.ps1
param(
  [string]$BrandOrange = '#F38B2B',
  [string]$SplashBg    = '#000000',
  [string]$MainActivityName = 'MainActivity'
)

function Ensure-Dir($Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force $Path | Out-Null }
}
function Write-Text($Path, [string]$Content) {
  Ensure-Dir (Split-Path $Path)
 if (Test-Path $Path) {
  $backupRoot = Join-Path $root "android\res_backups"
  if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Force $backupRoot | Out-Null }
  $backupFile = Join-Path $backupRoot (Split-Path $Path -Leaf)
  Copy-Item $Path $backupFile -Force
}

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
  Write-Host "Wrote $Path" -ForegroundColor Green
}

$root      = Get-Location
$resRoot   = Join-Path $root "android\app\src\main\res"
$values    = Join-Path $resRoot "values"
$valuesV31 = Join-Path $resRoot "values-v31"
$drawable  = Join-Path $resRoot "drawable"
$manifest  = Join-Path $root "android\app\src\main\AndroidManifest.xml"
$pubspec   = Join-Path $root "pubspec.yaml"

$colorsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="brand_orange">$BrandOrange</color>
    <color name="splash_bg">$SplashBg</color>
</resources>
"@
$transparentXml = @"
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="@android:color/transparent"/>
</shape>
"@
$stylesV31Xml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowSplashScreenBackground">@color/splash_bg</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/transparent</item>
        <item name="android:windowSplashScreenAnimationDuration">0</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/splash_bg</item>
    </style>
</resources>
"@
$stylesBaseXml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/splash_bg</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/splash_bg</item>
    </style>
</resources>
"@

Write-Text (Join-Path $values    "colors.xml")      $colorsXml
Write-Text (Join-Path $drawable  "transparent.xml") $transparentXml
Write-Text (Join-Path $valuesV31 "styles.xml")      $stylesV31Xml
Write-Text (Join-Path $values    "styles.xml")      $stylesBaseXml

if (Test-Path $manifest) {
  $m = Get-Content $manifest -Raw
  $pattern = '(<activity\b[^>]*android:name="[^"]*' + [regex]::Escape($MainActivityName) + '"[^>]*)(>)'
  if ($m -notmatch 'android:theme="@style/LaunchTheme"') {
    if ($m -match $pattern) {
      $m2 = $m -replace $pattern, '$1 android:theme="@style/LaunchTheme"$2'
      $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($manifest, $m2, $utf8NoBom)
      Write-Host "Updated theme in AndroidManifest.xml" -ForegroundColor Green
    } else {
      Write-Host "WARN, could not find MainActivity in AndroidManifest.xml" -ForegroundColor Yellow
    }
  } else {
    Write-Host "Manifest theme already set to @style/LaunchTheme" -ForegroundColor DarkGray
  }
} else {
  Write-Host "WARN, AndroidManifest.xml not found" -ForegroundColor Yellow
}

if (Test-Path $pubspec) {
  $p = Get-Content $pubspec -Raw
  if ($p -notmatch '(?m)^\s*-\s*assets/images/\s*$') {
    Write-Host ""
    Write-Host "NOTE, add this to pubspec.yaml if missing:" -ForegroundColor Yellow
    Write-Host "  flutter:" -ForegroundColor Yellow
    Write-Host "    uses-material-design: true" -ForegroundColor Yellow
    Write-Host "    assets:" -ForegroundColor Yellow
    Write-Host "      - assets/images/" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "Done, Android splash resources and theme are configured." -ForegroundColor Cyan
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  flutter clean" -ForegroundColor Cyan
Write-Host "  flutter pub get" -ForegroundColor Cyan
Write-Host "  flutter run" -ForegroundColor Cyan
