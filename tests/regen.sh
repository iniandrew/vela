#!/usr/bin/env bash
# Sandboxed test of site discovery + `vela regen`: stubs mise/nginx/systemctl/mkcert, touches nothing real.
set -euo pipefail
VELA=$(cd "$(dirname "$0")/.." && pwd)/bin/vela
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T"/{bin,home,cfg,data,state,run,php/8.5,php/8.4,parked/a,parked/b/public,parked/www.c,parked/.hidden,other/proj}
touch "$T/parked/a/.php84"   # stub mise reads this marker as "site wants 8.4"

cat >"$T/bin/mise" <<STUB
#!/usr/bin/env bash
case \$1 in
  where) v=\${2#php@}; [[ -d $T/php/\$v ]] && echo $T/php/\$v || exit 1 ;;
  current) [[ -e .php84 ]] && echo 8.4.1 || echo 8.5.12 ;;
  which) echo $T/bin/mkcert ;;
esac
STUB
cat >"$T/bin/nginx" <<'STUB'
#!/usr/bin/env bash
[[ ${STUB_NGINX_FAIL:-0} == 1 ]] && { echo "nginx: [emerg] stub failure" >&2; exit 1; }
exit 0
STUB
cat >"$T/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
case $* in *is-active*) exit 3 ;; *is-enabled*) exit 1 ;; esac
exit 0
STUB
cat >"$T/bin/mkcert" <<'STUB'
#!/usr/bin/env bash
while (( $# )); do case $1 in -cert-file) : >"$2"; shift ;; -key-file) : >"$2"; shift ;; esac; shift; done
STUB
chmod +x "$T"/bin/*

export HOME=$T/home XDG_CONFIG_HOME=$T/cfg XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/state XDG_RUNTIME_DIR=$T/run
export PATH=$T/bin:$PATH
C=$T/cfg/vela
fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -q -- "$2" "$1" || fail "$1 lacks '$2'"; }

"$VELA" park "$T/parked" >/dev/null
has "$C/nginx/sites/a.conf" 'server_name a.test \*.a.test'
has "$C/nginx/sites/a.conf" 'php-8.4.sock'                    # per-site PHP via mise
has "$C/nginx/sites/b.conf" "root \"$T/parked/b/public\""      # public/ preferred
has "$C/nginx/sites/b.conf" 'php-8.5.sock'
[[ -f $C/nginx/sites/c.conf ]] || fail "www. prefix not stripped"
[[ ! -e $C/nginx/sites/.hidden.conf ]] || fail "hidden dir served"
has "$C/nginx/sites/00-default.conf" 'return 404'
has "$C/nginx/nginx.conf" "include $C/nginx/sites/\*.conf"
has "$T/cfg/systemd/user/vela-sites.path" "PathChanged=$T/parked/b"

"$VELA" secure a >/dev/null
has "$C/nginx/sites/a.conf" 'listen 127.0.0.1:443 ssl'
[[ -f $C/certs/a.pem && -f $C/certs/a-key.pem ]] || fail "cert not created"

( cd "$T/other/proj" && "$VELA" link demo >/dev/null )
has "$C/nginx/sites/demo.conf" "root \"$T/other/proj\""
( cd "$T/other/proj" && "$VELA" unlink demo >/dev/null )
[[ ! -e $C/nginx/sites/demo.conf ]] || fail "unlink left conf"

cp "$C/nginx/sites/b.conf" "$T/b.before"; mkdir "$T/parked/new"
if STUB_NGINX_FAIL=1 "$VELA" regen --quiet 2>/dev/null; then fail "regen ignored nginx -t failure"; fi
[[ ! -e $C/nginx/sites/new.conf ]] || fail "bad config was installed"
"$VELA" regen --quiet; [[ -f $C/nginx/sites/new.conf ]] || fail "new site not picked up"
mkdir -p "$T/proj/app" "$T/proj/config"; touch "$T/proj/artisan"
if "$VELA" park "$T/proj" 2>/dev/null; then fail "park accepted a project root"; fi
echo "$T/proj" >>"$C/parked"; "$VELA" regen --quiet 2>/dev/null
[[ ! -e $C/nginx/sites/app.conf && ! -e $C/nginx/sites/config.conf ]] || fail "project subfolders served as sites"
echo "regen tests passed"
