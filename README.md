# ansible_morbucks

All-in-one Ansible setup for the **morbucks** server. One machine runs
everything: the build + deploy tooling, PostgreSQL, Caddy (reverse proxy with
automatic TLS), and the Elixir apps themselves.

It is a single-host distillation of `koopmans_deploy`: `install_deploy` +
`install_postgres` + a reverse proxy, merged onto one box, with **Caddy instead
of nginx** and **local build/deploy instead of pushing to a remote app server**.

## Layout of responsibilities

| Concern | Where it runs | Command |
|---|---|---|
| Provision the server | your workstation → morbucks (SSH) | `./provision.sh` |
| Copy this project onto morbucks | your workstation → morbucks | `./sync-to-morbucks.sh` |
| Build an Elixir release | on morbucks (local) | `./build.sh <app> <tag>` |
| Deploy a release | on morbucks (local) | `./deploy.sh <app> <tag> <env>` |

Provisioning is driven from your laptop so you can rebuild a dead machine fast.
Build/deploy run **on** morbucks (local connection) because everything — git
checkout, Postgres, releases, Caddy — lives there.

## What provisioning installs

`playbooks/provision.yml` applies four roles to morbucks:

- **common** – base packages, UTC/locale, admin users (`rkaper`, `ldr`) with
  their SSH keys, plus `ansible` + `rsync` so build/deploy can run locally.
- **build-toolchain** – the `deploy` build user, `asdf`, and every OS package
  needed to compile Erlang/Elixir and build Node assets. Language *versions* are
  **not** installed here.
- **postgres** – PostgreSQL 17 from PGDG, listening on loopback only by default.
- **caddy** – Caddy from the official repo, with a base `Caddyfile` that imports
  per-app vhosts from `/etc/caddy/sites/*.caddy`.
- **mail** – Postfix as a **loopback-only** SMTP relay. Apps send mail via
  `127.0.0.1:25`; nothing off the box can reach it. Install/refresh on its own
  with `ansible-playbook playbooks/install-mail.yml`.

## First-time setup

```bash
cd /home/rkaper/Programming/prive/ansible_morbucks

# 1. Secrets (optional but recommended)
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
$EDITOR group_vars/all/vault.yml          # set postgres password + ACME email
ansible-vault encrypt group_vars/all/vault.yml

# 2. Provision morbucks from your workstation
./provision.sh --ask-vault-pass           # drop the flag if you skipped the vault

# 3. Push this project onto the box so you can build/deploy there
./sync-to-morbucks.sh                      # -> root@morbucks:/opt/ansible_morbucks
```

## Deploying an app

1. Create `app_vars/<app>.yml` (see `app_vars/example_app.yml.example`). The
   filename must match the OTP app / release name.
2. Make sure the `deploy` user on morbucks can reach the git remote (add a
   deploy key to `/home/deploy/.ssh/`).
3. On morbucks:

```bash
cd /opt/ansible_morbucks
./build.sh  <app> <tag>          # git checkout <tag>, asdf install, mix release
./deploy.sh <app> <tag> <env>    # extract, config, db, migrate, systemd, caddy
```

`build.sh` reads the project's `.tool-versions` and installs exactly those
Erlang/Elixir/Node versions via asdf before running `mix release`.

`deploy.sh`:
- derives DB credentials (`<app>_<env>`) and generates/persists the app's
  `secret_key_base` + admin password on the box (so `app_vars` holds no secrets),
- extracts the artifact to `/opt/elixir_releases/<env>/<app>`,
- renders `config.exs` (if the release bundles `config.exs.j2`),
- ensures the PostgreSQL role + database and runs migrations (when
  `database: true`),
- installs and starts a `systemd` unit `<app>_<env>`,
- **writes `/etc/caddy/sites/<app>_<env>.caddy`** and reloads Caddy, so the app
  is reachable at its `domain` over HTTPS.

### Secrets

`app_vars/*.yml` are kept **secret-free** so they can be committed (even to a
public repo). Per app/env the deploy role persists `secret_key_base` and the
admin password under `/opt/elixir_releases/.secrets/<env>/<app>/` and reuses them
on later deploys; the admin password is printed at the end of each deploy. To
change one, edit the file there and redeploy. Only `group_vars/all/vault.yml`
(Postgres superuser password + ACME email, used at provisioning time) stays out
of git.

## How the Caddy reverse-proxy registration works

The base `/etc/caddy/Caddyfile` (from provisioning) contains only global options
plus:

```
import /etc/caddy/sites/*.caddy
```

Each deploy drops a snippet like:

```
orders.example.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:4060
}
```

Caddy obtains and renews the TLS certificate for that domain automatically via
ACME. For this to succeed the domain's DNS must point at morbucks and ports
**80 + 443 must be reachable from the internet**. While testing you can point at
Let's Encrypt staging by setting in `group_vars/all/main.yml`:

```yaml
caddy_global_extra: |
  acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
```

Set `http_port` and `domain` per environment in `app_vars/<app>.yml`. Omit
`domain` to keep an app internal (it still runs and listens on its port; Caddy
just won't publish it). For multiple upstreams behind one domain, use
`caddy_routes` (see the example app_vars).

## Sending email from apps

Postfix listens on `127.0.0.1:25` only. Point your app's mailer at it — e.g. a
Swoosh SMTP mailer with `relay: "127.0.0.1", port: 25, tls: false` and no auth
(loopback is a trusted network). This is exactly how `app_vars/machteldbakker_nl.yml`
wires `MachteldbakkerNl.Mailer`. Outbound goes direct-to-MX by default; set
`mail_relayhost` in `host_vars/morbucks.yml` to route through a provider.

## Operating a deployed app

A shell helper is installed globally, so from any root/sudo shell on morbucks:

```bash
my_app_prod remote     # remote console
my_app_prod rpc "..."  # rpc into the running node
systemctl status my_app_prod
journalctl -u my_app_prod -f
```

## Notes / prerequisites not handled here

- **Firewall**: open 80/443 (and 22) however you manage the network. Not
  configured by this project.
- **DNS**: point your app domains at morbucks before deploying, or ACME fails.
- **PostgreSQL** listens on loopback only by default. To allow LAN admin access
  set `postgres_listen_addresses` and `postgres_extra_hba_cidrs` in
  `host_vars/morbucks.yml`.
