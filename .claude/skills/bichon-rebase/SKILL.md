---
name: bichon-rebase
description: Refresh the Bichon patches (patches/) for a new upstream release — when Renovate's PR bumping UPSTREAM is red, when the owner says "обнови бишон до <версии>", "патчи не ложатся", or asks to move the patches to a new tag. Applies with three-way merge, resolves conflicts by what each change is for, runs the checks, exports and commits the patches. Never pushes on its own.
---

# Refresh the patches for a new upstream release

The repository keeps Bichon changes as patches on an upstream tag (README.md, first table).
The job: make `patches/` apply cleanly to the tag in `UPSTREAM` and pass the checks, keeping
every change's behaviour as README.md ("What the fork adds") describes it.

## Before

1. Work on the branch of Renovate's PR (or a new branch `upstream-<tag>`), never on `main`.
2. Read the upstream release notes between the old and the new tag
   (`gh release view <tag> -R rustmailer/bichon`, and the compare view): breaking changes,
   moved files, renamed APIs the patches use. Note what touches the patched areas.
3. `UPSTREAM` holds the new tag (Renovate already set it; otherwise edit the second line).

## Apply

```
scripts/apply.sh --force
```

`git am --3way` stops at the first patch that does not apply. For each stop:

- `cd work && git am --show-current-patch=diff` — the patch; `git status` — the conflicts.
- Resolve by intent, not by text: what the change is for is in README.md and in the patch's
  commit message. Upstream may have done part of it (then drop that part), moved the code
  (follow it), or changed an API (adapt the call).
- Keep the change as small as upstream allows: new code in new files, a few hooks in
  upstream files (the existing patches follow this; keep it so).
- `git add <files> && git am --continue`. A patch upstream made obsolete: `git am --skip`,
  and say so in the report.

After the last patch: `cp -r ../overlay/. .` (apply.sh stops before the overlay when `am`
stops) — or rerun `scripts/apply.sh --force` once all patches are exported.

## Check

In `work/`, the same as CI (`.github/workflows/build.yml`):

```
mkdir -p web/dist && echo '<!doctype html><title>check</title>' > web/dist/index.html
.github/scripts/svesh-check.sh
cd web && npx --yes pnpm@<version from build.yml> install --frozen-lockfile \
  && npx --yes pnpm@<same> exec tsc -b \
  && npx --yes pnpm@<same> exec vitest run src/features/accounts src/features/users
```

A failure in the fork's code: fix it and `git commit --amend` in `work/` (the patch is one
commit on top of the tag). Upstream's own failing tests are not ours: note them in the
report — to tell, run that test on a clean `git -C work checkout upstream`.

If the check script's file list or coverage regexes no longer match (a fork file moved), fix
`overlay/.github/scripts/svesh-check.sh`, not `work/`.

## Export and commit

```
scripts/export.sh
scripts/apply.sh --force    # must apply cleanly from scratch now
git add UPSTREAM patches overlay README.md
git commit                  # message: "Upstream <tag>: <what changed in the patches>"
```

Update README.md when a change's behaviour or files moved. Commit messages of the patches
and of this repository are public: nothing private (no hosts, accounts, mail contents).

## Report to the owner

- Which patches applied as is, which needed changes and why, which were dropped.
- Check results, upstream test failures that are not ours.
- What in the release notes may matter for the deployed instance (data migrations, new
  settings). Pushing, merging and deploying are the owner's calls.
