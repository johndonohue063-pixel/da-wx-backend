param(
  [Parameter(Mandatory=$true)]
  [string]$Csv,
  [string]$Out = $(Join-Path (Split-Path -Parent $Csv) "national_corrected_d7_caponly.csv")
)
$ErrorActionPreference = "Stop"

if (!(Test-Path $Csv)) { throw "CSV not found: $Csv" }
$rows = Import-Csv $Csv
if (-not $rows -or $rows.Count -eq 0) { throw "CSV appears empty." }
$cols = $rows[0].PSObject.Properties.Name

function FindCol([string[]]$cands){
  foreach($c in $cols){ $lc=$c.ToLower(); foreach($k in $cands){ if ($lc -like "*$k*"){ return $c } } }
  return $null
}
$colProb   = FindCol @('wind outage probability','probability','prob %','prob')
$colCust   = FindCol @('predicted customers out','customers','cust')
$colImpact = FindCol @('predicted impact date','impact date','impact')
if (-not $colProb) { throw "Could not find a probability column." }

function ToNum($v){ if ($null -eq $v){return $null}; $s=([string]$v).Replace('%','').Replace(',','').Trim(); if($s -eq ''){$null}else{ [double]::Parse($s,[Globalization.CultureInfo]::InvariantCulture) } }
function ParseDateOrNull($x){ if (-not $x){$null}else{ try{ ([DateTimeOffset]$x).Date }catch{ $null } } }

$today   = (Get-Date).Date
$target  = $today.AddDays(7)
$targetLo= $target.AddDays(-1)
$targetHi= $target.AddDays(1)

$out = foreach($r in $rows){
  $prob = ToNum $r.$colProb
  $cust = if ($colCust){ ToNum $r.$colCust } else { $null }
  $imp  = if ($colImpact){ ParseDateOrNull $r.$colImpact } else { $null }

  $inD7 = $true
  if ($imp){ $inD7 = ($imp -ge $targetLo -and $imp -le $targetHi) }

  $newProb = $prob
  $newCust = $cust
  if ($inD7 -and $prob -ne $null){
    if ($prob -gt 16){ $newProb = 16.0 }
    if ($cust -ne $null -and $prob -gt 0){ $newCust = $cust * ($newProb / $prob) }
  }

  $h=@{}
  foreach($c in $cols){ $h[$c] = $r.$c }
  $h["$colProb (Adjusted)"] = if ($newProb -ne $null){ [Math]::Round($newProb,1) } else { $null }
  if ($colCust){ $h["$colCust (Adjusted)"] = if ($newCust -ne $null){ [Math]::Round($newCust) } else { $null } }
  New-Object psobject -Property $h
}

$out | Export-Csv -NoTypeInformation -Encoding UTF8 $Out
Write-Host "[OK] Wrote $Out" -ForegroundColor Green
