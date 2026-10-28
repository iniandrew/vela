#!/usr/bin/env bash
# End-to-end check against a real, installed vela (run after `vela install`).
set -euo pipefail
d=$(mktemp -d "$HOME/Vela/smoke.XXXXXX"); n=$(basename "$d"); trap 'rm -rf "$d"; vela unlink smoke2 2>/dev/null || true' EXIT
mkdir "$d/public"; echo '<?php echo PHP_VERSION;' >"$d/public/index.php"
fail() { echo "FAIL: $*" >&2; exit 1; }
code_is() { for _ in $(seq 20); do [[ $(curl -s -m 3 -o /dev/null -w '%{http_code}' "$1") == "$2" ]] && return 0; sleep 0.5; done; return 1; }
PHP=$(mise which php)
wait_for() { for _ in $(seq 20); do out=$(curl -fsS "$1" 2>/dev/null) && return 0; sleep 0.5; done; return 1; }

vela regen --quiet
wait_for "http://$n.test" || fail "http://$n.test unreachable (parked auto-discovery or DNS)"
[[ $out == "$("$PHP" -r 'echo PHP_VERSION;')"* ]] || fail "served PHP '$out' differs from global php"

vela secure "$n" >/dev/null
wait_for "https://$n.test" || fail "https failed without -k (mkcert CA not trusted?)"
code_is "http://$n.test" 301 || fail "http does not redirect"

( cd "$d" && vela link smoke2 >/dev/null )
wait_for "http://smoke2.test" || fail "alias smoke2 unreachable"
( cd "$d" && vela unlink smoke2 >/dev/null )
code_is "http://smoke2.test" 404 || fail "unlink did not 404"
echo "smoke passed"
