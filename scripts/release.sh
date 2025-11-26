#!/bin/bash

# HXUI Release Script
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

echo -e "${GREEN}HXUI Release Script${NC}"
echo "=================="
echo "Version: $VERSION"
echo ""

# Check if files exist
if [ ! -f "HXUI/HXUI.lua" ]; then
    echo -e "${RED}Error: HXUI/HXUI.lua not found${NC}"
    echo "Please run this script from the repository root"
    exit 1
fi

if [ ! -f "HXUI/patchNotes.lua" ]; then
    echo -e "${RED}Error: HXUI/patchNotes.lua not found${NC}"
    exit 1
fi

# Update HXUI.lua
echo -e "${YELLOW}Updating HXUI.lua...${NC}"
sed -i "s/addon\.version[[:space:]]*=[[:space:]]*'[0-9.]*'/addon.version   = '$VERSION'/" HXUI/HXUI.lua

# Update patchNotes.lua
echo -e "${YELLOW}Updating patchNotes.lua...${NC}"
sed -i "s/imgui\.BulletText(' UPDATE [0-9.]* ')/imgui.BulletText(' UPDATE $VERSION ')/" HXUI/patchNotes.lua

# Verify updates
echo ""
echo -e "${GREEN}Files updated successfully!${NC}"
echo ""
echo "HXUI.lua version:"
grep "addon.version" HXUI/HXUI.lua
echo ""
echo "patchNotes.lua version:"
grep "UPDATE" HXUI/patchNotes.lua | head -n 1
echo ""

if [ "$NO_TAG" = true ]; then
    echo -e "${YELLOW}Skipping git operations (--no-tag specified)${NC}"
    echo "Don't forget to commit these changes!"
    exit 0
fi

# Check if git is clean
if [ -n "$(git status --porcelain | grep -v '^?? release.sh')" ]; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    echo ""
    git status --short
    echo ""
    read -p "Continue with tagging anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Check if tag already exists
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag v$VERSION already exists${NC}"
    exit 1
fi

# Prompt for release description
echo ""
echo "Enter a brief description for this release:"
read -r DESCRIPTION

if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Release v$VERSION"
else
    DESCRIPTION="Release v$VERSION: $DESCRIPTION"
fi

# Create and push tag
echo ""
echo -e "${YELLOW}Creating git tag v$VERSION...${NC}"
git tag -a "v$VERSION" -m "$DESCRIPTION"

echo -e "${GREEN}Tag created successfully!${NC}"
echo ""
echo "To push the tag and trigger the release, run:"
echo -e "${GREEN}git push origin v$VERSION${NC}"
echo ""
echo "Or to push now:"
read -p "Push tag now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push origin "v$VERSION"
    echo ""
    echo -e "${GREEN}Release tag pushed! GitHub Actions will create the release.${NC}"
    echo "Check the Actions tab: https://github.com/tirem/HXUI/actions"
else
    echo "Tag created but not pushed. Push later with:"
    echo "  git push origin v$VERSION"
fi
