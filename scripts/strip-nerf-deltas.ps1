<#
.SYNOPSIS
  MINE vs PROD (upstream/main) vs NERF (../XIUInerf): reset files where mine matches NERF but not PROD.

.DESCRIPTION
  For each tracked file that exists in PROD and on disk under NERF:
  - If hash(mine) == hash(nerf) AND hash(nerf) != hash(prod) → copy PROD blob (NERF-only delta vs PROD).
  - If hash(mine) == hash(prod) → leave.
  - Else → report for review (mixed user + NERF, or user-only).

  Local XIUI.lua ↔ upstream XIUI/XIUI.lua; other paths ↔ XIUI/<path>.

.PARAMETER DryRun
  Reports only; no file writes.

.PARAMETER NerfRoot
  Default: ../XIUInerf

.PARAMETER ProdRef
  Default: upstream/main
#>
param(
    [switch] $DryRun,
    [string] $NerfRoot = '',
    [string] $ProdRef = 'upstream/main'
)

# Native git stderr is non-terminating in PS 7 but can surface as errors in PS 5; probes use SilentlyContinue.
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Build-ProdBlobMap {
    param([string] $Ref)
    $map = @{}
    $lines = git ls-tree -r $Ref
    foreach ($line in $lines) {
        if ($line -match '^(\d+)\s+blob\s+([a-f0-9]+)\s+(.+)$') {
            $map[$Matches[3]] = $Matches[2]
        }
    }
    return $map
}

function Resolve-ProdBlobPath {
    param([string] $LocalPath, [hashtable] $ProdMap)
    $n = $LocalPath -replace '\\', '/'
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($n -eq 'XIUI.lua') {
        [void]$candidates.Add('XIUI/XIUI.lua')
    } else {
        [void]$candidates.Add("XIUI/$n")
        [void]$candidates.Add($n)
    }
    foreach ($c in $candidates) {
        if ($ProdMap.ContainsKey($c)) { return $c }
    }
    return $null
}

function Write-ProdBlobToFile {
    param([string] $RepoRoot, [string] $UpstreamPath, [string] $DestPath)
    $dir = Split-Path $DestPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Start-Process -FilePath git -ArgumentList @('show', "${script:ProdRef}:${UpstreamPath}") `
        -RedirectStandardOutput $DestPath -NoNewWindow -Wait -PassThru -WorkingDirectory $RepoRoot
    if ($p.ExitCode -ne 0) {
        throw "git show failed: ${UpstreamPath} -> $DestPath"
    }
}

$repo = Get-RepoRoot
Set-Location $repo
$script:ProdRef = $ProdRef

if (-not $NerfRoot) {
    $NerfRoot = Join-Path (Split-Path $repo -Parent) 'XIUInerf'
}
if (-not (Test-Path $NerfRoot)) {
    throw "NERF root not found: $NerfRoot"
}

Write-Host "Building upstream blob map for $ProdRef ..."
$prodBlobMap = Build-ProdBlobMap -Ref $ProdRef
Write-Host "Upstream blob entries: $($prodBlobMap.Count)"

$reportDir = Join-Path $repo 'scripts/.nerf-strip-report'
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logReset = Join-Path $reportDir "reset-to-prod-$stamp.txt"
$logReview = Join-Path $reportDir "review-$stamp.txt"
$logNoProd = Join-Path $reportDir "no-upstream-path-$stamp.txt"
$logNoNerf = Join-Path $reportDir "no-nerf-file-$stamp.txt"

$lines = git ls-files
$resetCount = 0
$skipSameAsProd = 0
$reviewCount = 0
$noProd = 0
$noNerf = 0

foreach ($rel in $lines) {
    $rel = $rel -replace '\\', '/'
    $up = Resolve-ProdBlobPath -LocalPath $rel -ProdMap $prodBlobMap
    if (-not $up) {
        Add-Content -Path $logNoProd -Value $rel
        $noProd++
        continue
    }

    $nerfFile = Join-Path $NerfRoot $rel
    if (-not (Test-Path $nerfFile)) {
        Add-Content -Path $logNoNerf -Value $rel
        $noNerf++
        continue
    }

    $prodHash = $prodBlobMap[$up]

    $minePath = Join-Path $repo $rel
    $mineHash = (git hash-object -- $minePath).Trim()
    $nerfHash = (git hash-object -- $nerfFile).Trim()

    if ($mineHash -eq $prodHash) {
        $skipSameAsProd++
        continue
    }

    if ($mineHash -eq $nerfHash -and $nerfHash -ne $prodHash) {
        Add-Content -Path $logReset -Value $rel
        $resetCount++
        if (-not $DryRun) {
            $outPath = Join-Path $repo $rel
            Write-ProdBlobToFile -RepoRoot $repo -UpstreamPath $up -DestPath $outPath
        }
        continue
    }

    Add-Content -Path $logReview -Value "$rel`tmixed or user-only (mine!=prod and not pure NERF blob)"
    $reviewCount++
}

$summary = @"
strip-nerf-deltas.ps1
DryRun=$DryRun  ProdRef=$ProdRef  NerfRoot=$NerfRoot
Reset to PROD (mine==nerf!=prod): $resetCount
Already match PROD:              $skipSameAsProd
Needs review:                    $reviewCount
No path in upstream (new?):      $noProd
No file in NERF tree:            $noNerf
Report dir: $reportDir
"@
Write-Host $summary
