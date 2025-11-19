Param(
    # Path to your Flutter app
    [string]$AppPath = "C:\Users\JohnDonohue\dev\divergentalliance",
    # Dart file that contains the Local preview widget
    [string]$DartFileRel = "lib\screens\weather_center.dart"
)

Write-Host "=== SWAP LOCAL PREVIEW WIDGET START ===" -ForegroundColor Cyan

$dartPath = Join-Path $AppPath $DartFileRel
if (-not (Test-Path $dartPath)) {
    Write-Host "Dart file not found: $dartPath" -ForegroundColor Red
    exit 1
}

# 1) Read the file
$text = [System.IO.File]::ReadAllText($dartPath)

# 2) Define the EXACT current widget code (OLD) and the NEW widget code
#    You MUST paste your actual current widget into $oldBlock once.
#    The script will then replace it with $newBlock.

$oldBlock = @'
/// TODO: PASTE YOUR CURRENT "Local threat preview" CARD HERE,
/// from the opening widget line down to the closing parenthesis/semicolon.
/// For example, something like:
///
/// Card(
///   child: Column(
///     children: [
///       Text('County,'),
///       Text('Computing local threat preview...'),
///     ],
///   ),
/// ),
'@

$newBlock = @'
Card(
  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: Color(0xFFFF9800), width: 1),
  ),
  child: _LocalThreatPreview(),  // new widget implemented below
),
'@

if (-not $text.Contains($oldBlock)) {
    Write-Host "Did not find the OLD local preview block in $dartPath" -ForegroundColor Yellow
    Write-Host "Edit Swap-LocalPreview.ps1 and replace the contents of `"oldBlock`" with your real widget code." -ForegroundColor Yellow
    exit 0
}

# 3) Backup and replace
$backup = "$dartPath.bak_localpreview_$(Get-Date -Format yyyyMMdd_HHmmss)"
Copy-Item $dartPath $backup -Force
Write-Host "Created backup: $backup" -ForegroundColor Green

$text = $text.Replace($oldBlock, $newBlock)

# 4) Append the new widget implementation at the end of the file (if not already present)
$marker = "_LocalThreatPreview extends"
if (-not $text.Contains($marker)) {

$widgetImpl = @'

class _LocalThreatPreview extends StatefulWidget {
  const _LocalThreatPreview({super.key});

  @override
  State<_LocalThreatPreview> createState() => _LocalThreatPreviewState();
}

class _LocalThreatPreviewState extends State<_LocalThreatPreview> {
  bool _loading = true;
  String _title = 'County,';
  String _subtitle = 'Computing local threat preview...';

  @override
  void initState() {
    super.initState();
    _loadLocalPreview();
  }

  Future<void> _loadLocalPreview() async {
    try {
      // 1) Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // 2) Call your backend for nearest county using lat/lon.
      //    You will need a tiny endpoint like:
      //    GET /report/county?lat=&lon=&hours=
      //    For now, we just show lat/lon so you can see it working.
      setState(() {
        _loading = false;
        _title = 'Your location';
        _subtitle =
            'Lat ${position.latitude.toStringAsFixed(3)}, Lon ${position.longitude.toStringAsFixed(3)}';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _subtitle = 'Local preview unavailable.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, color: Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Text(
                _title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

'@

  $text = $text + "`n" + $widgetImpl
  Write-Host "Appended _LocalThreatPreview implementation to $dartPath" -ForegroundColor Green
} else {
  Write-Host "_LocalThreatPreview already present; only swapped the card." -ForegroundColor Yellow
}

[System.IO.File]::WriteAllText($dartPath, $text)
Write-Host "Updated Local preview widget in $dartPath" -ForegroundColor Cyan
Write-Host "=== SWAP LOCAL PREVIEW WIDGET DONE ===" -ForegroundColor Cyan
