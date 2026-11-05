#!/bin/bash
# Upstream tag (UPSTREAM) + patches/ + overlay/ -> work/: the tree CI checks and builds, and
# the one to edit when a patch changes (then scripts/export.sh).
#   scripts/apply.sh [--force]   --force replaces an existing work/ (its changes are lost)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=$(grep -v '^#' UPSTREAM | head -n 1)
# The owner's mirror of rustmailer/bichon (main and tags, synced daily; it outlives upstream).
SOURCE_URL=https://github.com/svesh87/bichon.git
# Only when the mirror lacks the tag (its daily sync has not run yet).
UPSTREAM_URL=https://github.com/rustmailer/bichon.git

if [ -e work ]; then
    [ "${1:-}" = --force ] || { echo "work/ exists; scripts/apply.sh --force replaces it" >&2; exit 1; }
    rm -rf work
fi

if ! git -c advice.detachedHead=false clone --quiet --branch "$TAG" --filter=blob:none "$SOURCE_URL" work; then
    echo "tag $TAG not in the mirror yet; taking it from upstream" >&2
    rm -rf work
    git -c advice.detachedHead=false clone --quiet --branch "$TAG" --filter=blob:none "$UPSTREAM_URL" work
fi
# The base export.sh diffs against; a plain ref, so tag signing settings do not apply.
git -C work update-ref refs/tags/upstream HEAD
git -C work switch --quiet -c patches
# Authors come from the patches; the committer is whoever applies them. Unsigned: these commits
# only live in work/ and leave it as patches (owner's decision, 2026-11-05).
git -C work -c user.name="${GIT_COMMITTER_NAME:-bichon-patches}" \
    -c user.email="${GIT_COMMITTER_EMAIL:-bichon-patches@localhost}" \
    -c commit.gpgSign=false \
    am --quiet --3way --keep-cr "$PWD"/patches/*.patch
cp -r overlay/. work/
echo "work/ = $TAG + $(ls patches/*.patch | wc -l) patches + overlay"
