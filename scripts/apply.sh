#!/bin/bash
# Upstream tag (UPSTREAM) + patches/ + overlay/ -> work/: the tree CI checks and builds, and
# the one to edit when a patch changes (then scripts/export.sh).
#   scripts/apply.sh [--force]   --force replaces an existing work/ (its changes are lost)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=$(grep -v '^#' UPSTREAM | head -n 1)
UPSTREAM_URL=https://github.com/rustmailer/bichon.git
# Daily mirror of upstream's main and tags (its default branch "mirror" holds the sync).
MIRROR_URL=https://github.com/svesh87/bichon.git

if [ -e work ]; then
    [ "${1:-}" = --force ] || { echo "work/ exists; scripts/apply.sh --force replaces it" >&2; exit 1; }
    rm -rf work
fi

if ! git -c advice.detachedHead=false clone --quiet --branch "$TAG" --depth 1 "$UPSTREAM_URL" work; then
    echo "upstream unreachable or tag $TAG gone there; taking it from the mirror" >&2
    rm -rf work
    git -c advice.detachedHead=false clone --quiet --branch "$TAG" --depth 1 "$MIRROR_URL" work
fi
# The base export.sh diffs against; a plain ref, so tag signing settings do not apply.
git -C work update-ref refs/tags/upstream HEAD
git -C work switch --quiet -c patches
# Authors come from the patches; the committer is whoever applies them.
git -C work -c user.name="${GIT_COMMITTER_NAME:-bichon-patches}" \
    -c user.email="${GIT_COMMITTER_EMAIL:-bichon-patches@localhost}" \
    am --quiet --3way --keep-cr "$PWD"/patches/*.patch
cp -r overlay/. work/
echo "work/ = $TAG + $(ls patches/*.patch | wc -l) patches + overlay"
