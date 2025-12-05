# XIUI Release Script (PowerShell)
# Automates version updates and release tagging

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [switch]$NoTag
)

# Validate version format (should be like 1.3.7)
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Host "Error: Invalid version format" -ForegroundColor Red
    Write-Host "Version should be in format: X.Y.Z (e.g., 1.3.7)"
    exit 1
}

Write-Host "XIUI Release Script" -ForegroundColor Green
Write-Host "Version: $Version"
Write-Host ""

# Check if files exist
if (-not (Test-Path "XIUI/XIUI.lua")) {
    Write-Host "Error: XIUI/XIUI.lua not found" -ForegroundColor Red
    Write-Host "Please run this script from the repository root"
    exit 1
}

if (-not (Test-Path "XIUI/patchNotes.lua")) {
    Write-Host "Error: XIUI/patchNotes.lua not found" -ForegroundColor Red
    exit 1
}

# Safety Check 1: Verify we're on the main branch
Write-Host "Running release checks..." -ForegroundColor Yellow
$currentBranch = git rev-parse --abbrev-ref HEAD
if ($currentBranch -ne "main") {
    Write-Host "Error: Not on main branch (currently on: $currentBranch)" -ForegroundColor Red
    Write-Host "Releases must be created from the main branch"
    exit 1
}
Write-Host "[✓] On main branch" -ForegroundColor Green

# Safety Check 2: Verify clean working directory
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Host "Error: Working directory has uncommitted changes" -ForegroundColor Red
    Write-Host "Please commit or stash your changes before creating a release" -ForegroundColor Red
    Write-Host ""
    git status --short
    exit 1
}
Write-Host "[✓] Working directory is clean" -ForegroundColor Green

# Safety Check 3: Verify dev flags are disabled
$xiuiLuaContent = Get-Content "XIUI/XIUI.lua" -Raw

# Check Ashita 4.3 flag
if ($xiuiLuaContent -match '_XIUI_USE_ASHITA_4_3\s*=\s*true') {
    Write-Host "Error: _XIUI_USE_ASHITA_4_3 is set to true" -ForegroundColor Red
    Write-Host "This flag must be false for releases (most players use main branch)"
    Write-Host "Set it to false in XIUI/XIUI.lua before releasing"
    exit 1
}
Write-Host "[✓] Ashita 4.3 flag is disabled" -ForegroundColor Green

# Check hot reloading flag
if ($xiuiLuaContent -match '_XIUI_DEV_HOT_RELOADING_ENABLED\s*=\s*true') {
    Write-Host "Error: _XIUI_DEV_HOT_RELOADING_ENABLED is set to true" -ForegroundColor Red
    Write-Host "Hot reloading must be disabled for releases"
    Write-Host "Set it to false in XIUI/XIUI.lua before releasing"
    exit 1
}
Write-Host "[✓] Hot reloading is disabled" -ForegroundColor Green

# Safety Check 4: Fetch and verify we're up to date with origin
Write-Host "Fetching from origin..." -ForegroundColor Yellow
git fetch origin 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Could not fetch from origin (offline?)" -ForegroundColor Yellow
    $continue = Read-Host "Continue without verifying remote state? (y/N)"
    if ($continue -ne 'y' -and $continue -ne 'Y') {
        Write-Host "Aborted."
        exit 1
    }
} else {
    $localCommit = git rev-parse main
    $remoteCommit = git rev-parse origin/main
    if ($localCommit -ne $remoteCommit) {
        $behindCount = git rev-list --count main..origin/main
        $aheadCount = git rev-list --count origin/main..main

        if ($behindCount -gt 0) {
            Write-Host "Error: Local main is $behindCount commit(s) behind origin/main" -ForegroundColor Red
            Write-Host "Please pull the latest changes: git pull origin main"
            exit 1
        }
        if ($aheadCount -gt 0) {
            Write-Host "Warning: Local main is $aheadCount commit(s) ahead of origin/main" -ForegroundColor Yellow
            Write-Host "You have unpushed commits"
        }
    }
    Write-Host "[✓] Up to date with origin/main" -ForegroundColor Green
}
Write-Host ""

# Update XIUI.lua
Write-Host "Updating XIUI.lua..." -ForegroundColor Yellow
$xiuiContent = Get-Content "XIUI/XIUI.lua" -Raw
$xiuiContent = $xiuiContent -replace "addon\.version\s*=\s*'[\d\.]*'", "addon.version   = '$Version'"
Set-Content "XIUI/XIUI.lua" -Value $xiuiContent -NoNewline

# Update patchNotes.lua
Write-Host "Updating patchNotes.lua..." -ForegroundColor Yellow
$patchContent = Get-Content "XIUI/patchNotes.lua" -Raw
$patchContent = $patchContent -replace "imgui\.BulletText\('UPDATE [\d\.]+'\)", "imgui.BulletText('UPDATE $Version')"
Set-Content "XIUI/patchNotes.lua" -Value $patchContent -NoNewline

# Verify updates
Write-Host ""
Write-Host "Files updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "XIUI.lua version:"
Select-String -Path "XIUI/XIUI.lua" -Pattern "addon.version"
Write-Host ""
Write-Host "patchNotes.lua version (line 59):"
Select-String -Path "XIUI/patchNotes.lua" -Pattern "imgui\.BulletText\('UPDATE"
Write-Host ""

if ($NoTag) {
    Write-Host "Skipping git operations (--NoTag specified)" -ForegroundColor Yellow
    Write-Host "Don't forget to commit these changes!"
    exit 0
}

# Check if tag already exists
git rev-parse "v$Version" *>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Error: Tag v$Version already exists" -ForegroundColor Red
    exit 1
}

# Commit version changes
Write-Host "Committing version changes..." -ForegroundColor Yellow
git add XIUI/XIUI.lua XIUI/patchNotes.lua
git commit -m "Bump version to $Version"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create commit" -ForegroundColor Red
    exit 1
}
Write-Host "[✓] Version bump committed" -ForegroundColor Green

# Prompt for release description
Write-Host ""
$Description = Read-Host "Enter a brief description for this release (press Enter for default)"

if ([string]::IsNullOrWhiteSpace($Description)) {
    $Description = "Release v$Version"
} else {
    $Description = "Release v${Version}: $Description"
}

# Create tag
Write-Host ""
Write-Host "Creating git tag v$Version..." -ForegroundColor Yellow
git tag -a "v$Version" -m "$Description"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create tag" -ForegroundColor Red
    exit 1
}
Write-Host "[✓] Tag created successfully!" -ForegroundColor Green

# Show what will be pushed
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Ready to push to main (this is a release exception)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Changes to be pushed:" -ForegroundColor White
Write-Host "  • Commit: Bump version to $Version" -ForegroundColor White
Write-Host "  • Tag:    v$Version" -ForegroundColor White
Write-Host ""
Write-Host "File changes:" -ForegroundColor White
git show --stat HEAD
Write-Host ""
Write-Host "This will push BOTH the commit and tag to origin/main" -ForegroundColor Yellow
Write-Host ""
$push = Read-Host "Push to main now? (y/N)"
if ($push -eq 'y' -or $push -eq 'Y') {
    Write-Host ""
    Write-Host "Pushing commit and tag to origin/main..." -ForegroundColor Yellow
    git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to push commit to main" -ForegroundColor Red
        Write-Host "Tag is still local. Clean up with: git tag -d v$Version && git reset --hard HEAD~1"
        exit 1
    }
    git push origin "v$Version"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to push tag" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "[✓] Release v$Version pushed successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "GitHub Actions will now create the release." -ForegroundColor White
    Write-Host "Check the Actions tab: https://github.com/tirem/XIUI/actions" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "Commit and tag created but not pushed." -ForegroundColor Yellow
    Write-Host "Push later with:"
    Write-Host "  git push origin main && git push origin v$Version" -ForegroundColor White
    Write-Host ""
    Write-Host "Or to abort this release:"
    Write-Host "  git tag -d v$Version && git reset --hard HEAD~1" -ForegroundColor White
}
