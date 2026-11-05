#!/bin/bash
# Move the patches to a new upstream tag: apply them on the tag they were made for (the
# UPSTREAM of the last commit, where they apply cleanly), then `git rebase` onto the new tag in
# UPSTREAM — a real three-way merge, unlike `git am --3way` on a fresh clone.
#   scripts/rebase.sh [OLD_TAG]   OLD_TAG defaults to UPSTREAM as committed in HEAD
# Stops at conflicts in work/: resolve, `git add`, `git -c commit.gpgSign=false rebase
# --continue`; then scripts/export.sh. Commits in work/ are unsigned (they leave as patches).
set -euo pipefail
cd "$(dirname "$0")/.."
NEW=$(grep -v '^#' UPSTREAM | head -n 1)
OLD=${1:-$(git show HEAD:UPSTREAM | grep -v '^#' | head -n 1)}
[ "$OLD" != "$NEW" ] || { echo "UPSTREAM is still $OLD: set the new tag first" >&2; exit 1; }
SOURCE_URL=https://github.com/svesh87/bichon.git

rm -rf work
git -c advice.detachedHead=false clone --quiet --filter=blob:none --no-checkout "$SOURCE_URL" work
cd work
git config commit.gpgSign false
git config user.name "${GIT_COMMITTER_NAME:-bichon-patches}"
git config user.email "${GIT_COMMITTER_EMAIL:-bichon-patches@localhost}"
git switch --quiet --detach "refs/tags/$OLD"
git switch --quiet -c patches
git am --quiet --keep-cr ../patches/*.patch
echo "patches applied on $OLD; rebasing onto $NEW"
git update-ref refs/tags/upstream "refs/tags/$NEW^{commit}"
if git rebase --onto upstream "refs/tags/$OLD" patches; then
    cp -r ../overlay/. .
    echo "rebased cleanly onto $NEW; next: checks, then scripts/export.sh"
else
    echo "conflicts above: resolve in work/, git add, git rebase --continue; then cp -r overlay/. work/ and the checks" >&2
    exit 1
fi
