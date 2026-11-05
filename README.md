# Bichon, patched (svesh)

Changes to [Bichon](https://github.com/rustmailer/bichon) kept as patches on top of an
upstream release, not as a fork of its history:

| Path | What |
|---|---|
| `UPSTREAM` | the upstream tag the patches apply to (Renovate bumps it) |
| `patches/` | the changes, one `git format-patch` per change, applied in order with `git am` |
| `overlay/` | files copied over the patched tree as they are: the image's Dockerfile, `.dockerignore`, the checks script |
| `scripts/apply.sh` | upstream tag + patches + overlay → `work/` (ignored by git): the tree CI checks and builds |
| `scripts/export.sh` | commits in `work/` on top of the tag → `patches/` |
| `.github/workflows/build.yml` | apply → checks → image |
| `.claude/skills/bichon-rebase` | refresh the patches for a new upstream release |

Changing a patch: `scripts/apply.sh`, edit and commit in `work/` (amend the commit of that
change or add one; `git rebase -i upstream` there), `scripts/export.sh`, commit `patches/`.
## What the fork adds

The sync changes below form one **gentle mode for slow servers**, on only for accounts with
a "Chunk size" (or with `BICHON_IMAP_FETCH_CHUNK_KB` as the server default). Every other
account syncs exactly as upstream: batches of the account's batch size, no chunks, header
comparison in gap-fill, immediate reconnects.

- **MCP for AI agents** at `/mcp` (streamable HTTP, behind the API token guard), based on
  upstream's unfinished `feature/add-mcp` branch: `list_accounts`, `list_folders`,
  `sync_now`, `search_emails`, `get_email`, `get_thread`, `save_attachments`, `save_draft`.
  Nothing sends, deletes or moves mail. Code: `crates/server/src/mcp/`.
- **Drafts**: `save_draft` builds the message (reply threading, attachments) and APPENDs it
  to the account's `\Drafts` folder with `\Draft \Seen`.
- **Permissions** `account:sync` and `data:draft` (account roles), so an agent token gets
  read + sync + drafts without `account:manage`.
- **Service accounts** (`crates/core/src/users/service.rs`, `POST /api/v1/service-accounts`,
  "Service Account" button on the users page): a user record with `service_account = true`
  and no e-mail, password or WebUI token. Roles, account access and ACL work as for people;
  login is refused, a password or e-mail cannot be set, only API tokens act for it. After
  creation the UI opens its token dialog.
- **Chunked body download** (opt-in, `crates/core/src/imap/chunked.rs`): each message on
  its own in parts of `BODY.PEEK[]<offset.N>`, as Thunderbird does, instead of whole bodies
  of a batch in one FETCH. For servers that stall or drop the connection on large responses
  (Yandex). Applies to sync and to the body pass of gap-fill; not to gap-fill's header scan.
  The chunk size is the most one response may carry: messages no larger than it share one
  FETCH while their total stays within it (the batch size caps how many); larger ones go
  alone, in parts of that size.
  Per account: "Chunk size" in the account's download settings (`imap_fetch_chunk_kb`;
  empty = server default, `0` = off); server default: `BICHON_IMAP_FETCH_CHUNK_KB`.
- **Folders without new mail are skipped** (`archive/imap/download/unchanged.rs`): when a
  folder's UIDNEXT from the round's STATUS has not moved past the archived watermark, its
  incremental sync opens no connection.
- **Gap-fill by UID** (same file): with an unchanged UIDVALIDITY the UIDs not archived in
  the folder are the missing ones and are downloaded right away, without the header scan
  (upstream fetches `HEADER.FIELDS (MESSAGE-ID)` of every message; Yandex answers each batch
  in seconds, hours per folder). A changed UIDVALIDITY keeps the full header comparison.
- **Wait before reconnecting** (`crates/core/src/imap/reconnect.rs`): after a dropped
  connection every retry loop waits before the new LOGIN (upstream reconnected at once and
  waited afterwards; Yandex drops a LOGIN right after a drop).
- **Image** `ghcr.io/svesh87/bichon:<upstream>-<run>`: built from source
  (`overlay/docker/svesh.Dockerfile`), runs as uid 1000, by `.github/workflows/build.yml`.

## Checks

`overlay/.github/scripts/svesh-check.sh` (CI job `check`, before the image is built): rustfmt and
clippy without warnings in the fork's code, the fork's tests, line coverage of the fork's
files (MCP, chunked download, folder skip, service accounts; test files excluded) at least
80%. The MCP tests run the tools against a temporary store with imported messages and a
scripted IMAP server (drafts, sync); the download tests use upstream's scripted IMAP server;
the service account tests go through the REST API in a process of their own (settings are
set once per process). Upstream code is not judged: it carries warnings of its own.
The web job type-checks and runs the tests of the account and user pages.

## Settings

| Variable | Meaning |
|---|---|
| `BICHON_ENABLE_MCP=true` | mount `/mcp` |
| `BICHON_MCP_FILES_DIR` | file exchange directory: attachments are saved under `attachments/<account>/<date subject>/`, draft attachments are read only from inside it |
| `BICHON_LOG_FILTER` | per-target log levels, `RUST_LOG` syntax (e.g. `info,poem_mcpserver=warn`: the MCP library logs whole requests and responses at info); overrides `BICHON_LOG_LEVEL` |
| `BICHON_IMAP_RECONNECT_DELAYS` | gentle mode: seconds to wait before each reconnect after a dropped connection, comma-separated (default `30,60,120`, the last repeats; `0` = no wait). Default for accounts without their own "Reconnect delays" |
| `BICHON_IMAP_FETCH_CHUNK_KB` | chunked body download, part size in KB (4–65536; Thunderbird uses 136); unset or 0 — off, upstream behaviour. Default for accounts without their own "Chunk size" |

## Agent access

Create an account role holding `data:read`, `account:sync`, `data:draft`, then a service
account with that role on the accounts the agent may use (no system role needed), issue an
API token for it and send it as `Authorization: Bearer <token>`.

## Updating to a new upstream release

Renovate opens a PR bumping `UPSTREAM`; CI applies the patches to the new tag and runs the
checks. Green: review the upstream release notes and merge. Red: on the PR's branch run the
`bichon-rebase` skill (Claude Code): it applies the patches with three-way merge, resolves
conflicts by what each change is for (sections above), runs the checks, exports the patches
and commits them to the branch. By hand, the same:

```
scripts/apply.sh --force        # git am stops at the first patch that does not apply
cd work && git am --show-current-patch=diff   # fix, git add, git am --continue
.github/scripts/svesh-check.sh  # with web/dist stubbed, as in CI
cd .. && scripts/export.sh && git add patches UPSTREAM && git commit
```
