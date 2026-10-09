# Upload documents to the classifier host over SSH and show the result.
# Usage: .\upload.ps1 -Files .\LB-report.pdf,.\LB-minutes.docx -Target kali@192.168.1.50
param(
  [Parameter(Mandatory = $true)][string[]]$Files,
  [Parameter(Mandatory = $true)][string]$Target,
  [int]$Wait = 12
)

$remoteInput = "/srv/documents/input/"
$remoteRegistry = "/srv/documents/output/registry.csv"

foreach ($f in $Files) {
  if (-not (Test-Path $f)) { Write-Warning "File not found: $f"; continue }
  $name = Split-Path $f -Leaf
  if ($name -notlike "LB-*") {
    Write-Warning "$name does not start with LB- (it will be uploaded but the classifier will ignore it)"
  }
  scp $f "${Target}:$remoteInput"
  if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed: $name"; continue }
  Write-Host "Uploaded: $name"
}

Write-Host "Waiting $Wait s for the classifier..."
Start-Sleep -Seconds $Wait
ssh $Target "tail -n $($Files.Count) $remoteRegistry"
