# vela usage guide

vela serves your local projects at `https://<name>.test` using nginx, PHP-FPM and a tiny DNS server, all running as your own user (no containers, no root daemons). PHP and Node versions come from [mise](https://mise.jdx.dev). Databases and other services are optional addons.

- [Install](#install)
- [Quick start](#quick-start)
- [Sites: park vs link](#sites-park-vs-link)
- [HTTPS](#https)
- [PHP versions](#php-versions)
- [Xdebug](#xdebug)
- [Node](#node)
- [Addons (databases, Redis, search, storage)](#addons-databases-redis-search-storage)
- [Using addons from Laravel](#using-addons-from-laravel)
- [Day to day](#day-to-day)
- [WSL](#wsl)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Where things live](#where-things-live)

## Install

```
./install.sh        # or: curl -fsSL https://raw.githubusercontent.com/iniandrew/vela/main/install.sh | bash
```

`install.sh` puts the `vela` command on your PATH and runs `vela install`, which:

1. detects your distro and installs the packages vela needs (nginx, dnsmasq, ...), skipping any tool you already have. Build libraries are installed only when something gets compiled (a mise PHP, or a source-built addon such as Postgres or Redis);
2. installs mise and adds its activation to bash, zsh and fish;
3. sets up `.test` DNS, ports 80/443 for an unprivileged nginx, and a local certificate authority (mkcert, unless you already have it);
4. if you already have PHP (from your distro, Homebrew, asdf or phpenv), offers to use it instead of compiling, after warning you if that version has known security holes. Otherwise it asks which PHP versions to compile (each takes 5 to 10 minutes) and which one is the global default. See [Using your system PHP](#using-your-system-php);
5. asks about Node (skipped if you already have node or nvm), Xdebug and addons.

Everything optional can be added later. Rerun `vela install` at any time; it is safe to repeat.

Useful flags (accepted by `install.sh` and `vela install`):

```
--php=8.5,8.4        versions to compile, first one is the default (skips the system PHP check)
--node=ask|lts|skip
--xdebug=ask|yes|no
--addons=ask|none|postgres@17,redis:podman
--yes                no prompts, take the defaults (your own PHP if you have one and it is not affected by known CVEs, else PHP 8.5; no Xdebug, no addons)
--deps-only          only install distro packages, build libraries included
```

**After the install, your current terminal does not know about mise yet.** Run `exec fish` (or `exec zsh` / `exec bash`), or open a new terminal. Until then `php` and the addon client tools are "command not found".

## Quick start

```
mkdir -p ~/Vela/hello
echo '<?php echo "hello from PHP ", PHP_VERSION;' > ~/Vela/hello/index.php
curl http://hello.test
```

Any folder inside `~/Vela` is served automatically; no command needed. A new Laravel project:

```
cd ~/Vela
composer create-project laravel/laravel blog
# open http://blog.test
```

## Sites: park vs link

There are two ways to get a site, and mixing them up is the most common mistake.

| | `vela park` | `vela link` |
|---|---|---|
| For | a folder that **contains** many projects | **one** project, wherever it lives |
| Run it | in the parent folder (like `~/Vela`) | inside the project |
| Site name | each subfolder's name | the project folder's name, or the name you give |

```
cd ~/Vela && vela park              # every subfolder becomes <folder>.test (already done for ~/Vela)
cd ~/code/my-app && vela link       # my-app.test
cd ~/code/my-app && vela link shop  # shop.test
vela unlink [name]
vela forget [dir]                   # stop serving a parked folder
vela sites                          # table of sites, PHP version and https state
vela open [name]                    # open in the browser
```

Rules:

- `vela park` refuses a project folder (one with `artisan`, `composer.json` or an `index.php`), because it would serve `app`, `config`, `database` and so on as separate sites. Use `vela link` for those.
- The site name is the folder name in lowercase. A leading `www.` is removed. Hidden folders are ignored.
- Subdomains work too: `admin.my-app.test` is served by the same site as `my-app.test`.
- The web root is `public/` when it exists, otherwise the folder itself.
- Several names can point at the same project: run `vela link` with different names from the same folder.
- New folders are picked up automatically, usually within a second. You can force a refresh with `vela regen`.

## HTTPS

```
vela secure [name]      # https://<name>.test, http redirects to https
vela unsecure [name]
vela link shop --secure # link and secure in one step
```

Certificates come from mkcert, and its local authority is installed into your system and browser trust stores during `vela install`, so there are no browser warnings. If a browser still complains (Firefox sometimes does), restart it. Wildcard certificates cover `*.<name>.test` as well.

## PHP versions

```
vela php:list                   # installed versions; also flags versions affected by known CVEs
vela php:install 8.4            # compile another version
vela use 8.4                    # change the global default
vela isolate 8.3                # this site only (run inside the project)
vela isolate 8.3 --site=shop    # or name the site
vela unisolate
vela php:ext redis [ver]        # install and enable a PECL extension (defaults to the global PHP)
```

`vela isolate` writes a `mise.local.toml` in the project, so `php`, `composer` and `artisan` in that folder use the same version as the web server. Consider adding `mise.local.toml` to your `.gitignore`. mise config files must be trusted: if mise asks, run `mise trust`.

**Security note.** PHP 8.2.34 and older 8.2, 8.3.35 and older, 8.4.26 and older, and 8.5.11 and older are affected by CVE-2026-109618 and CVE-2026-109619 ("PHP2Shell"): unauthenticated remote code execution, reported as actively exploited. The fixed releases are 8.2.35, 8.3.36, 8.4.27 and 8.5.12. PHP 8.1 and older have no upstream fix. vela warns and asks before installing an affected version, and `vela php:list` flags ones you already have.

**Extensions.** Builds include the common Laravel extensions (list below). For anything else, `vela php:ext <name> [ver]` builds it through PECL, writes `conf.d/<name>.ini` and restarts that version's PHP-FPM. It does nothing if the extension is already loaded. There is no `php.ini` to edit: extensions are enabled by `.ini` files in the PHP version's `conf.d` directory (`$(mise where php@8.5)/conf.d`), and you can put your own settings there too.

Installed PHP builds include: bcmath, curl, gd, intl, mbstring, mysqli and pdo_mysql, pdo_pgsql, pdo_sqlite, sodium, openssl, zip, xsl, gmp, bz2, soap, sockets, pcntl and opcache, plus composer.

### Using your system PHP

If you already installed PHP yourself, vela can serve sites with it instead of compiling its own. It looks in these places:

- your distro: `/usr/bin/php` plus its `php-fpm` package
- Homebrew: `/home/linuxbrew/.linuxbrew/opt/php` and `php@8.x` (or `$HOMEBREW_PREFIX`, or `~/.linuxbrew`)
- asdf: `~/.asdf/installs/php/<version>` (or `$ASDF_DATA_DIR`)
- phpenv: `~/.phpenv/versions/<version>` (or `$PHPENV_ROOT`)

```
vela use system                 # use a PHP you installed; asks which one if there are several
vela use 8.5                    # back to a mise-compiled PHP
vela php:list                   # mise versions, then the ones vela found elsewhere
```

vela serves PHP through php-fpm, so the PHP you pick needs one. Homebrew and the asdf PHP plugin build it by default. With phpenv, make sure your build includes it (`sbin/php-fpm` in the version's folder). For the distro PHP, vela needs the `php-fpm` package, plus the extensions Laravel uses (pdo_sqlite, pdo_mysql, pdo_pgsql, intl, gd, zip, bcmath, sodium, openssl, mbstring, curl, dom) and composer. `vela install` and `vela use system` list whatever is missing and offer to install it with your package manager (for example `php-fpm php-intl` on Arch, `php8.4-fpm php8.4-mysql` on Debian/Ubuntu). On Arch, extensions that ship inside the `php` package but are turned off are enabled in a `vela.ini` in PHP's `conf.d` directory, which `vela uninstall` removes again.

For Homebrew, asdf and phpenv, vela warns about missing extensions but leaves installing them to that tool.

vela picks the global PHP in this order: the mise global version, then a PHP you installed (the one chosen with `vela use system` first, then distro, Homebrew, asdf, phpenv; only ones that have php-fpm), then the newest PHP mise has installed. `vela php:ext <name>` on the distro PHP installs the distro package (for example `php-redis`) instead of building it with PECL. On Homebrew, asdf or phpenv PHP, install extensions with that tool. Xdebug for your own PHP comes from your distro's xdebug package (or pecl for Homebrew, asdf, phpenv); `vela xdebug:install` only handles mise builds. `vela isolate` still uses mise versions.

**Security.** vela checks your own PHP's version against the PHP2Shell fixes (see the security note above). If it is older, `vela install`, `vela use system`, `vela link` and other site commands, and `vela php:list` warn you and suggest `vela php:install <ver> && vela use <ver>`. `vela install` and `vela use system` then ask before using it, defaulting to no. Distros sometimes backport a fix without changing the version number, so check your distro's security tracker before trusting or dismissing the warning.

## Xdebug

```
vela xdebug:install [ver]       # defaults to the global PHP
vela xdebug:remove [ver]
```

Xdebug starts in trigger mode on port 9003, so it costs nothing until you ask for it. For the browser, use an Xdebug helper extension (or add `?XDEBUG_TRIGGER=1` to the URL). For the command line, run `XDEBUG_TRIGGER=1 php artisan ...`.

## Node

If you had no Node or nvm, `vela install` offers to install the LTS version through mise. Otherwise your existing setup is left alone. You can always do it yourself: `mise use -g node@lts`, or per project `mise use node@22`.

## Addons (databases, Redis, search, storage)

Nothing is installed by default. Add what you need:

```
vela service:available          # catalog with versions and ports
vela service:add                # interactive picker: checkboxes, then a version list per service
vela service:add postgres 17    # or directly
vela service:list               # id, port, method, state, credentials
```

| Service | Versions offered | Port | Default credentials |
|---|---|---|---|
| mysql | 8.4, 8.0, 9.7 (any version mise knows) | 3306 | user `root`, no password |
| mariadb | 11.8, 10.11, 12.3, 13.0 | 3306 | user `root`, no password |
| postgres | 17, 18, 16, 15, 14 (any version mise knows) | 5432 | user `root`, no password |
| redis | 7.4, 8.4 (any version mise knows) | 6379 | no password |
| meilisearch | 1 | 7700 | no master key |
| minio | 2025-09-07, 2025-07-23, 2024-03-05 | 9000 (console 9001) | `root` / `password` |
| rustfs | 1 | 9100 (console 9101) | `root` / `password` |
| mongodb | 7.0, 8.0 | 27017 | no auth |

MySQL and MariaDB both default to 3306, so give the second one another port: `--port 3307`.

### Credentials

Each add asks "Use the default credentials?". Answer no to choose your own user and password (typed twice, hidden). For scripts:

```
vela service:add postgres 17 --user app --password 's3cret'
```

- MySQL and MariaDB: a custom non-root user gets all privileges; `root` stays passwordless on localhost.
- Postgres: credentials are fixed when the data directory is first created. To change them, `vela service:remove <id> --purge` and add it again.
- MinIO and RustFS need a username of 3+ and a password of 8+ characters.
- MongoDB is started without authentication.
- Passwords are stored in `~/.config/vela/services/<id>.env` (mode 600) and never appear in process lists.

### Native or container

```
vela service:add redis 8.4 --via native     # default
vela service:add postgres 17 --via podman   # official image, bound to 127.0.0.1
```

The container options (`podman`, `docker`) appear only if you have them installed. Both methods keep data in `~/.local/share/vela/data/<id>`. Docker needs your user in the `docker` group; podman rootless is recommended. MinIO is native only: its official binaries and images are no longer published, so vela compiles it from source with Go (a few minutes).

### Managing services

```
vela service:start|stop|restart <id>    # ids look like postgres-17, redis-8.4
vela service:logs <id>
vela service:default <id>               # which version owns psql, redis-cli, mysql ...
vela service:remove <id> [--purge]      # --purge also deletes the data
```

**Redis and PHP.** Laravel's default Redis client is phpredis, which PHP does not ship with. Adding a Redis addon builds the `redis` extension for every installed PHP version automatically, and any PHP you install later gets it too while a Redis addon exists. You do not need to do anything.

After each native install vela asks whether to make that version the default. The default owns the client tools on your PATH: `psql`, `pg_dump`, `pg_restore`, `createdb`, `dropdb`, `redis-cli`, `mysql`, `mysqldump`, `mariadb` and friends. Server programs such as `postgres` are not on your PATH on purpose; vela runs them for you. If you try one directly, mise prints `No version is set for shim`; that is expected.

## Using addons from Laravel

Everything listens on `127.0.0.1` only. In `.env`:

```
# Postgres (default credentials)
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=myapp
DB_USERNAME=root
DB_PASSWORD=

# MySQL / MariaDB
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=

# Redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=null

# Meilisearch (Laravel Scout)
SCOUT_DRIVER=meilisearch
MEILISEARCH_HOST=http://127.0.0.1:7700
MEILISEARCH_KEY=

# MinIO / RustFS (S3 compatible)
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=root
AWS_SECRET_ACCESS_KEY=password
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=myapp
AWS_ENDPOINT=http://127.0.0.1:9000
AWS_USE_PATH_STYLE_ENDPOINT=true
```

Create the database first, for example `createdb -h 127.0.0.1 -U root myapp` (Postgres) or `mysql -h 127.0.0.1 -u root -e 'create database myapp'`. For RustFS use port 9100 in `AWS_ENDPOINT`. Create the bucket from the console (port 9001 for MinIO, 9101 for RustFS).

## Day to day

```
vela status          # what is running
vela stop            # stop nginx, DNS, PHP-FPM and all addons
vela start
vela restart
vela regen           # rebuild the nginx config from your sites (also starts nginx if it is down)
```

vela starts at login and keeps running after you log out. Logs live in the journal:

```
journalctl --user -u vela-nginx
journalctl --user -u 'vela-fpm@*'
journalctl --user -u vela-dns
vela service:logs <id>
```

## WSL

vela is not tested on WSL. WSL1 cannot run it (no systemd). On WSL2, `.test` needs extra setup: once so WSL itself resolves it, and once more so Windows browsers do.

### Inside WSL

WSL writes its own `/etc/resolv.conf`, which bypasses systemd-resolved, so the `.test` route vela adds is never used. Hand DNS over to systemd-resolved before `vela install` (or rerun `vela install` afterwards):

1. Install systemd-resolved and keep WSL's current DNS server as its upstream. Read the server first, because installing the package can replace `/etc/resolv.conf`:

   ```
   up=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)   # WSL's DNS, e.g. 10.255.255.254
   sudo apt install systemd-resolved                             # Debian/Ubuntu; other distros ship it with systemd
   sudo mkdir -p /etc/systemd/resolved.conf.d
   printf '[Resolve]\nDNS=%s\n' "$up" | sudo tee /etc/systemd/resolved.conf.d/wsl.conf
   sudo systemctl enable --now systemd-resolved
   sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
   ```

2. Stop WSL from rewriting `/etc/resolv.conf`. `/etc/wsl.conf` should contain:

   ```
   [boot]
   systemd=true

   [network]
   generateResolvConf=false
   ```

3. Restart WSL: run `wsl --shutdown` in PowerShell, then open your distro again.

4. Run `vela install`, then check that both lookups print an address, `127.0.0.1` for the first:

   ```
   getent hosts blog.test
   getent hosts github.com
   ```

If DNS tunneling is off (older Windows or WSL), WSL's DNS server is the Windows host's address on the WSL network, which can change after a Windows reboot. If outside names stop resolving later, update `DNS=` in `/etc/systemd/resolved.conf.d/wsl.conf` and run `sudo systemctl restart systemd-resolved`.

### From Windows

Windows browsers use Windows DNS, not WSL's, and the Windows hosts file has no wildcards. Add one line per site to `C:\Windows\System32\drivers\etc\hosts` (open your editor as Administrator):

```
127.0.0.1 blog.test
```

WSL forwards Windows' `127.0.0.1:80` and `:443` to vela. If a site still does not load, check that nothing on Windows holds port 80: `netstat -ano | findstr :80` in PowerShell.

## Troubleshooting

**`php` or `vela` tools: command not found, right after install.** Your terminal started before mise was set up. Run `exec fish` (or `exec zsh` / `exec bash`), or open a new terminal.

**"Unable to connect" to a `.test` site.** Run `vela status`. If `vela-nginx` is not active, run `vela regen`, which starts it, then check `journalctl --user -u vela-nginx`. Also confirm something else is not holding port 80: `ss -ltnp | grep ':80 '`.

**`.test` does not resolve.** Check `resolvectl query anything.test`; it should answer `127.0.0.1`. If not, `systemctl status vela-dns-link` and `vela status`. Leftovers from another local-dev tool (such as Lerd) that point DNS at a dead local server can break this; look at `resolvectl status` for stray `127.0.0.1:5300` entries.

**One project shows up as many sites (`app.test`, `config.test`, ...).** You ran `vela park` inside the project. Run `vela forget` there, then `vela link`.

**`error: no PHP installed` although `php` works.** vela serves PHP through php-fpm, from a mise build or from a PHP you installed (distro, Homebrew, asdf, phpenv). If your PHP comes from the distro, run `vela use system`: it installs the missing `php-fpm` package and extensions after asking. A Homebrew, asdf or phpenv PHP without `sbin/php-fpm` must be rebuilt with fpm enabled. Otherwise, use `vela php:install 8.5`. PHP from other places is not detected.

**The wrong PHP version is used.** `vela sites` shows the version per site. Set one with `vela isolate <ver>`, or change the default with `vela use <ver>`. A version recorded in a project's mise config that is not installed falls back to the global version.

**`Class "Redis" not found`.** The phpredis extension is missing for the PHP version that site uses. Run `vela php:ext redis <ver>` (see `vela sites` for the version), then reload the page.

**A site returns 502.** PHP-FPM for that version is down: `vela status`, then `journalctl --user -u 'vela-fpm@*'`.

**nginx refuses a new config.** `vela regen` tests the config first and keeps the previous one if the test fails, printing nginx's error.

**Browser shows a certificate warning.** Restart the browser. If it persists, run `mkcert -install` again.

**Port already in use when adding an addon.** Choose another: `vela service:add mysql 8.4 --port 3307`.

## Uninstall

```
vela uninstall            # removes units and the system files vela created; keeps config and addon data
vela uninstall --purge    # also deletes config, certificates and addon data
```

This does not remove mise, the PHP and addon versions it installed, the distro packages, or the mkcert authority in your trust store. Remove versions with `mise uninstall`, and packages with your package manager.

## Where things live

| Path | What |
|---|---|
| `~/.config/vela/` | parked folders, links, secure markers, certificates, generated nginx and FPM config, addon settings |
| `~/.config/vela/services/<id>.env` | one addon's settings and credentials (mode 600) |
| `~/.local/share/vela/data/<id>/` | addon data |
| `~/.config/systemd/user/vela*` | the systemd user units |
| `~/.local/share/mise/installs/` | PHP and addon builds |
| `/etc/systemd/system/vela-dns-link.service`, `/etc/sysctl.d/99-vela-ports.conf`, `/etc/udev/rules.d/90-vela-nm-unmanaged.rules` | the three system files, removed by `vela uninstall` |
