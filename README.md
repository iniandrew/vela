# vela

A native, container-free take on Laravel Herd for Linux. nginx + php-fpm + dnsmasq serve every folder as `<name>.test`; PHP/Node versions come from [mise](https://mise.jdx.dev); databases and other services are opt-in addons.

Supports systemd distros: Arch family, Debian/Ubuntu, Fedora/RHEL, openSUSE.

## Install

    ./install.sh                      # from a clone
    curl -fsSL https://raw.githubusercontent.com/iniandrew/vela/main/install.sh | bash

`install.sh` only fetches `vela` and puts it on your PATH, then runs `vela install`, which does the real work:
distro packages (Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE), mise, nginx/DNS/TLS setup, then asks which PHP versions to compile, plus Node, Xdebug and addons. Rerun `vela install` any time.

Flags (accepted by both): `--php=8.5,8.4` (first = default) `--node=ask|lts|skip` `--xdebug=ask|yes|no` `--addons=ask|none|postgres@17,redis:podman` `--yes` `--deps-only`.

PHP 8.2 to 8.5 must be at least 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 to be safe from CVE-2026-109618 and CVE-2026-109619 (PHP2Shell); vela warns and asks before installing an affected version, and `vela php:list` flags installed ones.

## Use

Full guide: [USAGE.md](USAGE.md).

    cd ~/Vela && laravel new blog     # http://blog.test, no command needed
    cd ~/code/app && vela link        # http://app.test
    vela secure app                   # https via mkcert
    vela isolate 8.4 --site=app       # per-site PHP (writes mise.local.toml)
    vela sites

Run `vela help` for the full list.

## Addons

    vela service:available
    vela service:add postgres 17
    vela service:add minio --via podman --port 9100
    vela service:list

Each addon is a systemd user unit. `--via native` (default) uses mise, a pinned download, or a source build; `--via podman|docker` runs the official image on 127.0.0.1. Data lives in `~/.local/share/vela/data/<id>`.

## Notes

- Ports 80/443 are bound by an unprivileged nginx via `net.ipv4.ip_unprivileged_port_start=80`.
- `.test` DNS: a `vela0` dummy link routes only `~test` to a local dnsmasq (systemd-resolved), or NetworkManager's dnsmasq plugin when resolved is off.
- MinIO no longer publishes binaries, so the native route compiles it with Go (a few minutes).
- Uninstall: `vela uninstall [--purge]`.

## Tests

    tests/regen.sh     # sandboxed, no sudo, stubs mise/nginx
    tests/smoke.sh     # needs an installed vela
