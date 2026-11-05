#!/bin/bash
# work/ commits on top of the upstream tag -> patches/ (one patch per commit, in order). The
# overlay is not part of the patches: files under overlay/ are edited there, not in work/.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d work/.git ] || { echo "no work/: run scripts/apply.sh first" >&2; exit 1; }

overlay_paths=$(cd overlay && find . -type f | sed 's#^\./#:(exclude)#')
if git -C work diff --quiet upstream HEAD -- $(cd overlay && find . -type f | sed 's#^\./##'); then :; else
    echo "work/ commits touch overlay files; move those changes to overlay/" >&2; exit 1
fi

rm -f patches/*.patch
# shellcheck disable=SC2086
git -C work format-patch --quiet --zero-commit --no-signature -o ../patches upstream..HEAD \
    -- . $overlay_paths
ls patches/*.patch | wc -l
