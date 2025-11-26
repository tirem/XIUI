# HXUI Release Script (PowerShell)
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

Write-Host "HXUI Release Script" -ForegroundColor Green
Write-Host "==================="
Write-Host "Version: $Version"
Write-Host ""

# Check if files exist
if (-not (Test-Path "HXUI/HXUI.lua")) {
    Write-Host "Error: HXUI/HXUI.lua not found" -ForegroundColor Red
    Write-Host "Please run this script from the repository root"
    exit 1
}

if (-not (Test-Path "HXUI/patchNotes.lua")) {
    Write-Host "Error: HXUI/patchNotes.lua not found" -ForegroundColor Red
    exit 1
}

# Update HXUI.lua
Write-Host "Updating HXUI.lua..." -ForegroundColor Yellow
$hxuiContent = Get-Content "HXUI/HXUI.lua" -Raw
$hxuiContent = $hxuiContent -replace "addon\.version\s*=\s*'[\d\.]*'", "addon.version   = '$Version'"
Set-Content "HXUI/HXUI.lua" -Value $hxuiContent -NoNewline

# Update patchNotes.lua
Write-Host "Updating patchNotes.lua..." -ForegroundColor Yellow
$patchContent = Get-Content "HXUI/patchNotes.lua" -Raw
$patchContent = $patchContent -replace "imgui\.BulletText\(' UPDATE [\d\.]* '\)", "imgui.BulletText(' UPDATE $Version ')"
Set-Content "HXUI/patchNotes.lua" -Value $patchContent -NoNewline

# Verify updates
Write-Host ""
Write-Host "Files updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "HXUI.lua version:"
Select-String -Path "HXUI/HXUI.lua" -Pattern "addon.version"
Write-Host ""
Write-Host "patchNotes.lua version:"
Select-String -Path "HXUI/patchNotes.lua" -Pattern "UPDATE" | Select-Object -First 1
Write-Host ""

if ($NoTag) {
    Write-Host "Skipping git operations (--NoTag specified)" -ForegroundColor Yellow
    Write-Host "Don't forget to commit these changes!"
    exit 0
}

# Check if git is clean
$gitStatus = git status --porcelain | Where-Object { $_ -notmatch '^\?\? release\.' }
if ($gitStatus) {
    Write-Host "Warning: You have uncommitted changes" -ForegroundColor Yellow
    Write-Host ""
    git status --short
    Write-Host ""
    $continue = Read-Host "Continue with tagging anyway? (y/N)"
    if ($continue -ne 'y' -and $continue -ne 'Y') {
        Write-Host "Aborted."
        exit 1
    }
}

# Check if tag already exists
$tagExists = git rev-parse "v$Version" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Error: Tag v$Version already exists" -ForegroundColor Red
    exit 1
}

# Prompt for release description
Write-Host ""
$Description = Read-Host "Enter a brief description for this release (press Enter for default)"

if ([string]::IsNullOrWhiteSpace($Description)) {
    $Description = "Release v$Version"
} else {
    $Description = "Release v$Version: $Description"
}

# Create tag
Write-Host ""
Write-Host "Creating git tag v$Version..." -ForegroundColor Yellow
git tag -a "v$Version" -m "$Description"

Write-Host "Tag created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To push the tag and trigger the release, run:" -ForegroundColor White
Write-Host "git push origin v$Version" -ForegroundColor Green
Write-Host ""
$push = Read-Host "Push tag now? (y/N)"
if ($push -eq 'y' -or $push -eq 'Y') {
    git push origin "v$Version"
    Write-Host ""
    Write-Host "Release tag pushed! GitHub Actions will create the release." -ForegroundColor Green
    Write-Host "Check the Actions tab: https://github.com/tirem/HXUI/actions"
} else {
    Write-Host "Tag created but not pushed. Push later with:"
    Write-Host "  git push origin v$Version"
}
