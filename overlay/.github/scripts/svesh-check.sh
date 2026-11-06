#!/bin/sh
# Checks of the fork's own code: rustfmt, clippy without warnings, the fork's tests,
# line coverage >= MIN_COVERAGE. Own code = the files below (tests in *tests.rs files are
# not counted); upstream code is not judged here: it has warnings of its own.
#
# Needs: rustfmt, clippy, llvm-tools-preview, cargo-llvm-cov, python3; and web/dist
# (or pnpm) for the server's build script.
set -eu

MIN_COVERAGE=${MIN_COVERAGE:-80}
OWN_FILES="crates/server/src/mcp/*.rs
crates/core/src/imap/chunked.rs
crates/core/src/imap/chunked_tests.rs
crates/core/src/imap/reconnect.rs
crates/core/src/imap/reconnect_tests.rs
crates/core/src/archive/imap/download/unchanged.rs
crates/core/src/archive/imap/download/unchanged_tests.rs
crates/core/src/logger/filter.rs
crates/core/src/users/service.rs
crates/server/src/rest/api/service_accounts.rs
crates/server/src/tests/service_account_tests.rs
crates/server/src/svesh_import.rs
crates/core/src/store/tantivy/svesh_ru.rs
crates/core/src/store/tantivy/svesh_ru_tests.rs
crates/core/src/backup/svesh_crypt.rs
crates/core/src/backup/svesh_crypt_tests.rs
crates/core/src/backup/svesh_engine.rs
crates/core/src/backup/svesh_engine_tests.rs
crates/core/src/backup/svesh_retention_tests.rs"
OWN_RE='^(crates/server/src/(mcp/|svesh_import|rest/api/service_accounts|tests/service_account_tests)|crates/core/src/imap/(chunked|reconnect)|crates/core/src/archive/imap/download/unchanged|crates/core/src/logger/filter|crates/core/src/users/service|crates/core/src/store/tantivy/svesh_ru|crates/core/src/backup/svesh_)'

echo "== rustfmt"
# shellcheck disable=SC2086 # the list is globs
rustfmt --edition 2021 --check $OWN_FILES 2>/dev/null

echo "== clippy"
log=$(mktemp)
cargo clippy --locked -p bichon-core -p bichon-server --all-targets --message-format=short >"$log" 2>&1 || {
    cat "$log"
    exit 1
}
if grep -E "$OWN_RE" "$log"; then
    echo "clippy: warnings in the fork's code"
    exit 1
fi

echo "== tests + coverage"
cargo llvm-cov clean --workspace
cargo llvm-cov --no-report --locked -p bichon-server --lib -- mcp::
# Own process: SETTINGS are set once per process and the MCP tests need theirs.
cargo llvm-cov --no-report --locked -p bichon-server --lib -- tests::service_account_tests
cargo llvm-cov --no-report --locked -p bichon-core --lib -- imap::chunked imap::reconnect archive::imap::download logger::filter store::tantivy::svesh_ru backup::svesh_crypt backup::engine::svesh_engine backup::retention::svesh_tests
cargo llvm-cov report --json --summary-only --output-path cov.json
python3 -I - "$MIN_COVERAGE" <<'EOF'
import json, re, sys
minimum = float(sys.argv[1])
own = re.compile(r"/crates/(server/src/(mcp/|svesh_import\.rs|rest/api/service_accounts\.rs)|core/src/imap/(chunked|reconnect)\.rs|core/src/archive/imap/download/unchanged\.rs|core/src/logger/filter\.rs|core/src/users/service\.rs|core/src/store/tantivy/svesh_ru\.rs|core/src/backup/svesh_(crypt|engine)\.rs)")
files = [f for f in json.load(open("cov.json"))["data"][0]["files"]
         if own.search(f["filename"]) and not f["filename"].endswith("tests.rs")]
covered = sum(f["summary"]["lines"]["covered"] for f in files)
count = sum(f["summary"]["lines"]["count"] for f in files)
for f in files:
    lines = f["summary"]["lines"]
    print(f"  {f['filename'].split('/crates/', 1)[-1]}: {lines['percent']:.1f}% of {lines['count']} lines")
percent = 100.0 * covered / count
print(f"Fork line coverage: {percent:.1f}% (minimum {minimum:.0f}%)")
sys.exit(0 if percent >= minimum else 1)
EOF
