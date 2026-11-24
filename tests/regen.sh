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
  where) v=\${2#php@}; [[ \${STUB_NO_MISE_PHP:-0} != 1 && -d $T/php/\$v ]] && echo $T/php/\$v || exit 1 ;;
  current) [[ \${STUB_NO_MISE_PHP:-0} == 1 ]] && exit 0; [[ -e .php84 ]] && echo 8.4.1 || echo 8.5.12 ;;
  which) [[ \$2 == mkcert ]] && echo $T/bin/mkcert || exit 1 ;;
esac
STUB
cat >"$T/bin/nginx" <<'STUB'
#!/usr/bin/env bash
[[ ${STUB_NGINX_FAIL:-0} == 1 ]] && { echo "nginx: [emerg] stub failure" >&2; exit 1; }
exit 0
STUB
cat >"$T/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
case $* in *is-active*) [[ ${STUB_UP:-0} == 1 ]] && exit 0; exit 3 ;; *is-enabled*) exit 1 ;; esac
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
( cd "$T/other/proj" && "$VELA" unlink demo.test >/dev/null )   # name as `vela sites` prints it
[[ ! -e $C/nginx/sites/demo.conf ]] || fail "unlink left conf"

cp "$C/nginx/sites/b.conf" "$T/b.before"; mkdir "$T/parked/new"
if STUB_NGINX_FAIL=1 "$VELA" regen --quiet 2>/dev/null; then fail "regen ignored nginx -t failure"; fi
[[ ! -e $C/nginx/sites/new.conf ]] || fail "bad config was installed"
"$VELA" regen --quiet; [[ -f $C/nginx/sites/new.conf ]] || fail "new site not picked up"
mkdir -p "$T/proj/app" "$T/proj/config"; touch "$T/proj/artisan"
if "$VELA" park "$T/proj" 2>/dev/null; then fail "park accepted a project root"; fi
echo "$T/proj" >>"$C/parked"; "$VELA" regen --quiet 2>/dev/null
[[ ! -e $C/nginx/sites/app.conf && ! -e $C/nginx/sites/config.conf ]] || fail "project subfolders served as sites"

# vela share: a marker from a live process adds a catch-all server on its port; a dead one is ignored
mkdir -p "$T/run/vela/share"; echo "8800 $$" >"$T/run/vela/share/b"; "$VELA" regen --quiet
has "$C/nginx/sites/b.conf" 'listen 127.0.0.1:8800'
has "$C/nginx/sites/b.conf" 'server_name _'
sleep 0 & dead=$!; wait "$dead"
echo "8800 $dead" >"$T/run/vela/share/b"; "$VELA" regen --quiet
! grep -q 'server_name _' "$C/nginx/sites/b.conf" || fail "stale share marker still served"
rm "$T/run/vela/share/b"
cat >"$T/bin/cloudflared" <<'STUB'
#!/usr/bin/env bash
case $* in
  *localhost:5173*) echo "2026-11-24T00:00:00Z INF |  https://vite-x.trycloudflare.com  |" >&2; exec sleep 5 ;;
  *) sleep 0.3; echo "2026-11-24T00:00:00Z INF |  https://app-x.trycloudflare.com  |" >&2; sleep 0.5
     cp "$STUB_ENV" "$STUB_ENV.during"   # .env as vela left it while sharing
     if [[ ${STUB_EDIT:-0} == 1 ]]; then echo X=1 >>"$STUB_ENV"; fi
     sleep 0.5 ;;
esac
STUB
chmod +x "$T/bin/cloudflared"
mkdir -p "$T/parked/b/bootstrap"; touch "$T/parked/b/artisan"
printf '<?php
return Application::configure()
    ->withMiddleware(function ($middleware) {})
    ->create();
' >"$T/parked/b/bootstrap/app.php"
printf 'APP_URL=http://b.test\nSESSION_DOMAIN=.b.test\n' >"$T/parked/b/.env"; printf 'http://[::1]:5173' >"$T/parked/b/public/hot"
mkdir -p "$T/parked/b/config"; echo '<?php return [];' >"$T/parked/b/config/sanctum.php"
export STUB_ENV=$T/parked/b/.env; cp "$STUB_ENV" "$T/env.orig"
out=$(STUB_UP=1 "$VELA" share b --via cloudflared --vite 2>&1)
for want in 'APP_URL=https://app-x.trycloudflare.com' 'trustProxies' 'allowedHosts' 'loadEnv' 'was http://b.test' '.env restored'; do
  [[ $out == *"$want"* ]] || fail "share output lacks '$want': $out"
done
for want in 'APP_URL=https://app-x.trycloudflare.com' 'VITE_SHARE_URL=https://vite-x.trycloudflare.com' 'SESSION_DOMAIN=null' \
            'SANCTUM_STATEFUL_DOMAINS=localhost,localhost:3000,127.0.0.1,127.0.0.1:8000,::1,b.test,app-x.trycloudflare.com'; do
  has "$STUB_ENV.during" "$want"
done
cmp -s "$STUB_ENV" "$T/env.orig" || fail "share did not restore .env: $(cat "$STUB_ENV")"
[[ ! -e $T/parked/b/.env.backup ]] || fail "share left .env.backup"
# .env edited while sharing: vela keeps it and leaves the original in .env.backup; the next share refuses
out=$(STUB_UP=1 STUB_EDIT=1 "$VELA" share b --via cloudflared 2>&1 </dev/null)
[[ $out == *"changed while sharing"* ]] || fail "share did not warn about the edited .env: $out"
has "$STUB_ENV" 'X=1'
cmp -s "$T/parked/b/.env.backup" "$T/env.orig" || fail ".env.backup is not the original .env"
err=$(STUB_UP=1 "$VELA" share b --via cloudflared 2>&1 </dev/null) && fail "share overwrote .env.backup"
[[ $err == *".env.backup exists"* ]] || fail "share does not explain the leftover .env.backup: $err"
mv "$T/parked/b/.env.backup" "$STUB_ENV"
[[ ! -e $T/run/vela/share/b ]] || fail "share left its marker"
! grep -q 'server_name _' "$C/nginx/sites/b.conf" || fail "share left its nginx server"
err=$("$VELA" share b 2>&1 </dev/null) && fail "share ran without a tunnel choice"
[[ $err == *"vela start"* ]] || fail "share does not refuse when vela is stopped: $err"

# no mise PHP: fall back to the distro PHP and its php-fpm (7.9 so a real one never matches)
mkdir -p "$T/sys"
printf '#!/usr/bin/env bash\necho 7.9.1\n' >"$T/sys/php"
cat >"$T/sys/php-fpm" <<'STUB'
#!/usr/bin/env bash
[[ $1 == -v ]] && { echo "PHP 7.9.1 (fpm-fcgi)"; exit 0; }
echo "fpm $*"
STUB
chmod +x "$T"/sys/*
export STUB_NO_MISE_PHP=1 VELA_SYS_PHP=$T/sys/php HOMEBREW_PREFIX=$T/nobrew
unset ASDF_DATA_DIR PHPENV_ROOT
"$VELA" regen --quiet
has "$C/nginx/sites/b.conf" 'php-7.9.sock'
[[ $("$VELA" fpm-run 7.9) == "fpm --nodaemonize --fpm-config $C/fpm/7.9.conf" ]] || fail "fpm-run did not use the system php-fpm"
rm "$T/sys/php-fpm"
err=$("$VELA" regen --quiet 2>&1) && fail "regen succeeded without any php-fpm"
[[ $err == *"vela use system"* ]] || fail "missing php-fpm error does not mention 'vela use system': $err"
list=$("$VELA" php:list 2>&1)
[[ $list == *"7.9.1"*distro* && $list == *PHP2Shell* && $list == *"vela php:install 8.5"* ]] || fail "php:list does not flag the old system PHP: $list"

# asdf PHP (one prefix per version) is used when the distro PHP has no php-fpm
a=$T/home/.asdf/installs/php/8.3.6; mkdir -p "$a/bin" "$a/sbin"
printf '#!/usr/bin/env bash\necho 8.3.6\n' >"$a/bin/php"
printf '#!/usr/bin/env bash\necho "asdf-fpm $*"\n' >"$a/sbin/php-fpm"; chmod +x "$a/bin/php" "$a/sbin/php-fpm"
"$VELA" regen --quiet
has "$C/nginx/sites/b.conf" 'php-8.3.sock'
[[ $("$VELA" fpm-run 8.3) == "asdf-fpm --nodaemonize --fpm-config $C/fpm/8.3.conf" ]] || fail "fpm-run did not use the asdf php-fpm"
echo "regen tests passed"
