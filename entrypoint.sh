#!/bin/bash

# Note that this does not use pipefail
# because if the grep later doesn't match any deleted files,
# which is likely the majority case,
# it does not exit with a 0, and I only care about the final exit.
set -eo

# Ensure SVN username and password are set
# IMPORTANT: while secrets are encrypted and not viewable in the GitHub UI,
# they are by necessity provided as plaintext in the context of the Action,
# so do not echo or use debug mode unless you want your secrets exposed!
if [[ -z "$SVN_URL" ]]; then
    echo "Set the SVN_URL param"
    exit 1
fi

if [[ -z "$SVN_DIR" ]]; then
    echo "Set the SVN_DIR param"
    exit 1
fi
if [[ -z "$SVN_USERNAME" ]]; then
    echo "Set the SVN_USERNAME secret"
    exit 1
fi

if [[ -z "$SVN_PASSWORD" ]]; then
    echo "Set the SVN_PASSWORD secret"
    exit 1
fi
if [[ -z "$ASSETS_DIR" ]]; then
    echo "Set the ASSETS_DIR param"
    exit 1
fi

# Allow some ENV variables to be customized
if [[ -z "$SLUG" ]]; then
    SLUG=${GITHUB_REPOSITORY#*/}
fi
echo "ℹ︎ SLUG is $SLUG"
echo "ℹ︎ ASSETS_DIR is $ASSETS_DIR"

# By default we use root directory to upload on SVN
# But sometimes we need to upload files from `build` directory
if [[ -z "$SOURCE_DIR" ]]; then
    SOURCE_DIR=""
else
    echo "ℹ︎ Using custom directory to upload from - $SOURCE_DIR"
fi

# Checkout just trunk and assets for efficiency
# Tagging will be handled on the SVN level
echo "➤ Checking out .org repository..."
svn checkout --depth immediates "$SVN_URL" "$SVN_DIR"
cd "$SVN_DIR"
svn update --set-depth infinity assets
svn update --set-depth infinity trunk

echo "➤ Copying files..."
# Copy from current branch to /trunk, excluding dotorg assets
# The --delete flag will delete anything in destination that no longer exists in source
if [[ -e "$GITHUB_WORKSPACE/.distignore" ]]; then
    echo "ℹ︎ Using .distignore"
    rsync -rc --exclude-from="$GITHUB_WORKSPACE/.distignore" "$GITHUB_WORKSPACE/$SOURCE_DIR" trunk/ --delete --delete-excluded
else
    rsync -rc "$GITHUB_WORKSPACE/$SOURCE_DIR" trunk/ --delete --delete-excluded
fi

# Copy dotorg assets to /assets
if [[ -d "$GITHUB_WORKSPACE/$ASSETS_DIR/" ]]; then
    rsync -rc "$GITHUB_WORKSPACE/$ASSETS_DIR/" assets/ --delete
else
    echo "ℹ︎ No assets directory found; skipping..."
fi

# Add everything and commit to SVN
# The force flag ensures we recurse into subdirectories even if they are already added
# Suppress stdout in favor of svn status later for readability
echo "➤ Preparing files..."
svn add . --force > /dev/null

# SVN delete all deleted files
# Also suppress stdout here
svn status | grep '^\!' | sed 's/! *//' | xargs -I% svn rm %@ > /dev/null

# Copy tag locally to make this a single commit
echo "➤ Copying tag..."
svn cp "trunk" "tags/$VERSION"

# Fix screenshots getting force downloaded when clicking them
# https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/
svn propset svn:mime-type image/png assets/*.png || true
svn propset svn:mime-type image/jpeg assets/*.jpg || true

svn status

echo "➤ Committing files..."
svn commit -m "Update to version $VERSION from GitHub" --no-auth-cache --non-interactive  --username "$SVN_USERNAME" --password "$SVN_PASSWORD"

echo "✓ Plugin deployed!"
