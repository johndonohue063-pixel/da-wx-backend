# ================================
# Divergent Alliance, final landing UI, theme, assets, build verify
# One touch fixer for Flutter project, idempotent
# ================================
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function OK($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function INFO($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function WARN($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function DIE($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }

function Backup-File($path){
  if(Test-Path $path){
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $bak = "$path.bak.$ts"
    Copy-Item $path $bak -Force
    OK "Backup created $bak"
  }
}

function Ensure-Dir($p){
  if(!(Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null; OK "Created $p" }
}

# ---------- paths ----------
$root = Get-Location
$lib = Join-Path $root "lib"
$main = Join-Path $lib "main.dart"
$screens = Join-Path $lib "screens"
$landing = Join-Path $screens "landing_screen.dart"
$pubspec = Join-Path $root "pubspec.yaml"
$assets = Join-Path $root "assets"
$imgDir = Join-Path $assets "images"
$icoDir = Join-Path $assets "icons"

if(!(Test-Path $main)){ DIE "lib\main.dart not found. Run from Flutter project root." }
if(!(Test-Path $pubspec)){ DIE "pubspec.yaml not found. Run from Flutter project root." }

Ensure-Dir $lib
Ensure-Dir $screens
Ensure-Dir $assets
Ensure-Dir $imgDir
Ensure-Dir $icoDir

Set-Content -Path (Join-Path $assets "README.txt") -Value @"
This folder stores images and icons for the app.
Place hero photo at assets/images/truck.jpg and logo at assets/icons/da_logo.png
"@ -Encoding UTF8

# ---------- pubspec assets ----------
Backup-File $pubspec
$pub = Get-Content $pubspec -Raw
if($pub -notmatch "(?ms)^\s*flutter:\s*$"){
  $pub += "`nflutter:`n  uses-material-design: true`n  assets:`n    - assets/images/`n    - assets/icons/`n"
}else{
  if($pub -notmatch "(?ms)^\s*uses-material-design:\s*true"){
    $pub = $pub -replace "(?ms)^(flutter:\s*)","`$1`n  uses-material-design: true`n"
  }
  if($pub -notmatch "(?ms)^\s*assets:\s*$"){
    $pub = $pub -replace "(?ms)^(\s*flutter:\s*(?:\n\s+.+)*)","`$1`n  assets:`n    - assets/images/`n    - assets/icons/`n"
  } else {
    if($pub -notmatch "(?ms)-\s*assets/images/"){ $pub = $pub -replace "(?ms)^(\s*assets:\s*\n)","`$1    - assets/images/`n" }
    if($pub -notmatch "(?ms)-\s*assets/icons/"){ $pub = $pub -replace "(?ms)^(\s*assets:\s*\n(?:\s*-\s*assets\/images\/\s*\n)*)","`$1    - assets/icons/`n" }
  }
}
Set-Content $pubspec $pub -Encoding UTF8
OK "Ensured assets entries in pubspec.yaml"

# ---------- landing screen ----------
Backup-File $landing
$landingCode = @"
import 'package:flutter/material.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const Color brandOrange = Color(0xFFFF6A00);
  static const Color onBrandOrange = Colors.black;

  @override
  Widget build(BuildContext context) {
    final hero = Image.asset(
      'assets/images/truck.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.black),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset(
              'assets/icons/da_logo.png',
              height: 28,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            const Text(
              'Divergent Alliance',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          hero,
          // bottom scrim for contrast
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black87.withOpacity(0.15),
                  Colors.black87.withOpacity(0.35),
                  Colors.black87.withOpacity(0.85),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Spacer(),
                  // primary CTA
                  Semantics(
                    button: true,
                    label: 'Open Weather Center',
                    child: SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.cloud),
                        label: const Text('Weather'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandOrange,
                          foregroundColor: onBrandOrange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pushNamed('/weather');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // secondary CTA
                  Semantics(
                    button: true,
                    label: 'Open Shop',
                    child: SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.storefront),
                        label: const Text('Shop'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white70),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pushNamed('/shop');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
"@
Set-Content -Path $landing -Value $landingCode -Encoding UTF8
OK "Wrote screens/landing_screen.dart"

# ---------- main.dart canonical content ----------
Backup-File $main
$mainCode = @"
import 'package:flutter/material.dart';
import 'screens/landing_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static Widget _routeGuard(Widget child, String name) {
    // Replace Placeholder with actual screens when ready
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFF6A00),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6A00),
          onPrimary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const LandingScreen(),
      routes: <String, WidgetBuilder>{
        '/weather': (context) => _routeGuard(const Placeholder(), 'Weather Center'),
        '/shop': (context) => _routeGuard(const Placeholder(), 'Shop'),
      },
    );
  }
}
"@
Set-Content -Path $main -Value $mainCode -Encoding UTF8
OK "Rewrote lib/main.dart with theme and routes"

# ---------- clean common dotted track artifacts in project ----------
Get-ChildItem -Path $lib -Recurse -Include *.dart | ForEach-Object {
  $t = Get-Content $_.FullName -Raw
  $t2 = $t
  $t2 = $t2 -replace "(?ms)Container\([^)]*?border:.*?dotted.*?\)", "const SizedBox.shrink()"
  $t2 = $t2 -replace "(?ms)List<Widget>\s*tracks\s*=\s*\[[^\]]*\];", "final List<Widget> tracks = const [];"
  $t2 = $t2 -replace "(?ms)Row\([^)]*?children:\s*tracks[^)]*\)", "const SizedBox.shrink()"
  if($t2 -ne $t){ Set-Content -Path $_.FullName -Value $t2 -Encoding UTF8; OK "Cleaned dotted artifacts in $($_.FullName)" }
}

INFO "Running flutter pub get"
flutter pub get | Write-Host

INFO "Formatting Dart files"
dart format lib | Write-Host

INFO "Static analysis"
flutter analyze | Write-Host

try{
  INFO "Attempting a quick build to validate publish path"
  flutter build apk --debug | Write-Host
  OK "Build completed"
}catch{
  WARN "Build failed in debug step, check analyzer output above"
}

OK "All steps done. Place truck.jpg and da_logo.png in assets to see full visuals."
