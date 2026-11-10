#!/usr/bin/env bash
# Tests for oneleet-login. Usage: test_login.sh <path to oneleet-login>
# A fake `sudo` first on PATH records what the daemon CLI would receive and
# then behaves like it (reads the token file, deletes it, exits FAKE_RC).
set -euo pipefail

login=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tmp" "$work/log"

# The fake's interpreter is the bash running this test: the Nix build sandbox
# has no /usr/bin/env.
printf '#!%s\n' "$BASH" >"$work/bin/sudo"
cat >>"$work/bin/sudo" <<'FAKE'
printf '%s\n' "$@" >"$FAKE_LOG/argv"
file=$4
stat -c '%a' "$file" >"$FAKE_LOG/mode"
cat "$file" >"$FAKE_LOG/token"
rm -f "$file"
exit "${FAKE_RC:-0}"
FAKE
chmod +x "$work/bin/sudo"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# run <fake-rc> <stdin>: runs oneleet-login, prints its exit status
run() {
  rm -f "$work/log/"*
  local rc=0
  printf '%s' "$2" | PATH="$work/bin:$PATH" TMPDIR="$work/tmp" FAKE_LOG="$work/log" FAKE_RC="$1" \
    "$login" >"$work/log/out" 2>&1 || rc=$?
  echo "$rc"
}

# 1. A token is handed over in a private file, never on the command line.
rc=$(run 0 $'tok-secret-123\n\n')
[ "$rc" = 0 ] || fail "success case exited $rc: $(cat "$work/log/out")"
mapfile -t argv <"$work/log/argv"
case "${argv[0]}" in */bin/oneleet-cli) ;; *) fail "runs ${argv[0]}, not oneleet-cli" ;; esac
[ "${argv[1]}" = login ] || fail "second argument is ${argv[1]}, not login"
[ "${argv[2]}" = --enrollment-token-file ] || fail "third argument is ${argv[2]}"
grep -q tok-secret-123 "$work/log/argv" && fail "token appears on the command line"
[ "$(cat "$work/log/token")" = tok-secret-123 ] || fail "token file holds [$(cat "$work/log/token")]"
[ "$(cat "$work/log/mode")" = 600 ] || fail "token file mode is $(cat "$work/log/mode")"
[ -z "$(ls -A "$work/tmp")" ] || fail "temporary files left behind: $(ls -A "$work/tmp")"
echo "ok   token handed over privately"

# 2. A failed login keeps its exit status and still cleans up.
rc=$(run 3 $'tok-secret-123\n\n')
[ "$rc" = 3 ] || fail "failed login exited $rc, want 3"
[ -z "$(ls -A "$work/tmp")" ] || fail "temporary files left behind after failure"
echo "ok   failure status kept, cleaned up"

# 3. No token: nothing is run.
rc=$(run 0 $'\n\n')
[ "$rc" = 1 ] || fail "empty token exited $rc, want 1"
[ ! -e "$work/log/argv" ] || fail "sudo ran without a token"
echo "ok   empty token refused"

# 4. Closing stdin early (window closed) must not hang or crash before cleanup.
rc=$(run 0 'tok-secret-123')
[ "$rc" = 0 ] || fail "EOF after token exited $rc"
[ -z "$(ls -A "$work/tmp")" ] || fail "temporary files left behind on EOF"
echo "ok   EOF handled"
