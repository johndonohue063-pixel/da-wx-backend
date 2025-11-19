$ErrorActionPreference = "Stop"

function Save-Utf8($Path,$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path,$Text,$enc)
}

# Ensure the widget exists, create minimal one if missing
$widget = "lib\ui\widgets\spark_button.dart"
if(!(Test-Path $widget)){
  $code = @"
import 'package:flutter/material.dart';

class SparkButton extends StatelessWidget {
  const SparkButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 56,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        splashFactory: InkSparkle.splashFactory,
        child: Ink(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            image: const DecorationImage(
              image: AssetImage('assets/images/button_sparks.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Center(
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
"@
  $dir = Split-Path $widget -Parent
  if($dir -and !(Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Save-Utf8 $widget $code
  Write-Host "Created $widget"
}

# Fix bad package imports everywhere
$files = Get-ChildItem -Path .\lib -Recurse -Filter *.dart
foreach($f in $files){
  $t = Get-Content $f.FullName -Raw
  $changed = $false

  # back up once
  $bak = "$($f.FullName).bak"
  if(-not (Test-Path $bak)){ Copy-Item $f.FullName $bak -Force }

  if($t -match "package:divergentalliance/"){
    $t = $t -replace "package:divergentalliance/", "package:divergent_alliance/"
    $changed = $true
  }
  if($t -match "package:your_app/"){
    $t = $t -replace "package:your_app/", "package:divergent_alliance/"
    $changed = $true
  }

  # If SparkButton is used, ensure the correct import is present
  if($t -match "SparkButton\(" -and $t -notmatch "spark_button\.dart"){
    $t = $t -replace "(?m)^(import\s+['""]package:flutter/material.dart['""];)",
                    "`$1`r`nimport 'package:divergent_alliance/ui/widgets/spark_button.dart';"
    $changed = $true
  }

  if($changed){
    Save-Utf8 $f.FullName $t
  }
}

Write-Host "Imports corrected to package:divergent_alliance"
