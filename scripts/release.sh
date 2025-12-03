#!/bin/bash

# XIUI Release Script
# Automates version updates and release tagging

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version number required${NC}"
    echo "Usage: ./release.sh <version> [--no-tag]"
    echo "Example: ./release.sh 1.3.7"
    echo ""
    echo "Options:"
    echo "  --no-tag    Update version files only, don't create git tag"
    exit 1
fi

VERSION=$1
NO_TAG=false

# Check for --no-tag flag
if [ "$2" == "--no-tag" ]; then
    NO_TAG=true
fi

# Validate version format (should be like 1.3.7)
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format${NC}"
    echo "Version should be in format: X.Y.Z (e.g., 1.3.7)"
    exit 1
fi

echo -e "${GREEN}XIUI Release Script${NC}"
echo "=================="
echo "Version: $VERSION"
echo ""

# Check if files exist
if [ ! -f "XIUI/XIUI.lua" ]; then
    echo -e "${RED}Error: XIUI/XIUI.lua not found${NC}"
    echo "Please run this script from the repository root"
    exit 1
fi

if [ ! -f "XIUI/patchNotes.lua" ]; then
    echo -e "${RED}Error: XIUI/patchNotes.lua not found${NC}"
    exit 1
fi

# Safety Check 1: Verify we're on the main branch
echo -e "${YELLOW}Running pre-flight safety checks...${NC}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Not on main branch (currently on: $CURRENT_BRANCH)${NC}"
    echo "Releases must be created from the main branch"
    exit 1
fi
echo -e "${GREEN}[✓] On main branch${NC}"

# Safety Check 2: Verify clean working directory
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}Error: Working directory has uncommitted changes${NC}"
    echo -e "${RED}Please commit or stash your changes before creating a release${NC}"
    echo ""
    git status --short
    exit 1
fi
echo -e "${GREEN}[✓] Working directory is clean${NC}"

# Safety Check 3: Fetch and verify we're up to date with origin
echo -e "${YELLOW}Fetching from origin...${NC}"
if ! git fetch origin 2>/dev/null; then
    echo -e "${YELLOW}Warning: Could not fetch from origin (offline?)${NC}"
    read -p "Continue without verifying remote state? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
else
    LOCAL_COMMIT=$(git rev-parse main)
    REMOTE_COMMIT=$(git rev-parse origin/main)
    if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
        BEHIND_COUNT=$(git rev-list --count main..origin/main)
        AHEAD_COUNT=$(git rev-list --count origin/main..main)

        if [ "$BEHIND_COUNT" -gt 0 ]; then
            echo -e "${RED}Error: Local main is $BEHIND_COUNT commit(s) behind origin/main${NC}"
            echo "Please pull the latest changes: git pull origin main"
            exit 1
        fi
        if [ "$AHEAD_COUNT" -gt 0 ]; then
            echo -e "${YELLOW}Warning: Local main is $AHEAD_COUNT commit(s) ahead of origin/main${NC}"
            echo "You have unpushed commits"
        fi
    fi
    echo -e "${GREEN}[✓] Up to date with origin/main${NC}"
fi
echo ""

# Update XIUI.lua
echo -e "${YELLOW}Updating XIUI.lua...${NC}"
sed -i "s/addon\.version[[:space:]]*=[[:space:]]*'[0-9.]*'/addon.version   = '$VERSION'/" XIUI/XIUI.lua

# Update patchNotes.lua
echo -e "${YELLOW}Updating patchNotes.lua...${NC}"
sed -i "s/imgui\.BulletText(' UPDATE [0-9.]* ')/imgui.BulletText(' UPDATE $VERSION ')/" XIUI/patchNotes.lua

# Verify updates
echo ""
echo -e "${GREEN}Files updated successfully!${NC}"
echo ""
echo "XIUI.lua version:"
grep "addon.version" XIUI/XIUI.lua
echo ""
echo "patchNotes.lua version (line 59):"
grep "imgui\.BulletText(' UPDATE" XIUI/patchNotes.lua
echo ""

if [ "$NO_TAG" = true ]; then
    echo -e "${YELLOW}Skipping git operations (--no-tag specified)${NC}"
    echo "Don't forget to commit these changes!"
    exit 0
fi

# Check if tag already exists
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag v$VERSION already exists${NC}"
    exit 1
fi

# Commit version changes
echo -e "${YELLOW}Committing version changes...${NC}"
git add XIUI/XIUI.lua XIUI/patchNotes.lua
git commit -m "Bump version to $VERSION"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create commit${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Version bump committed${NC}"

# Prompt for release description
echo ""
echo "Enter a brief description for this release:"
read -r DESCRIPTION

if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Release v$VERSION"
else
    DESCRIPTION="Release v$VERSION: $DESCRIPTION"
fi

# Create tag
echo ""
echo -e "${YELLOW}Creating git tag v$VERSION...${NC}"
git tag -a "v$VERSION" -m "$DESCRIPTION"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create tag${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Tag created successfully!${NC}"

# Show what will be pushed
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${CYAN}Ready to push to main (this is a release exception)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo ""
echo "Changes to be pushed:"
echo "  • Commit: Bump version to $VERSION"
echo "  • Tag:    v$VERSION"
echo ""
echo "File changes:"
git show --stat HEAD
echo ""
echo -e "${YELLOW}This will push BOTH the commit and tag to origin/main${NC}"
echo ""
read -p "Push to main now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Pushing commit and tag to origin/main...${NC}"
    git push origin main
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to push commit to main${NC}"
        echo "Tag is still local. Clean up with: git tag -d v$VERSION && git reset --hard HEAD~1"
        exit 1
    fi
    git push origin "v$VERSION"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to push tag${NC}"
        exit 1
    fi
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}[✓] Release v$VERSION pushed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo "GitHub Actions will now create the release."
    echo -e "${CYAN}Check the Actions tab: https://github.com/tirem/XIUI/actions${NC}"
else
    echo ""
    echo -e "${YELLOW}Commit and tag created but not pushed.${NC}"
    echo "Push later with:"
    echo "  git push origin main && git push origin v$VERSION"
    echo ""
    echo "Or to abort this release:"
    echo "  git tag -d v$VERSION && git reset --hard HEAD~1"
fi
