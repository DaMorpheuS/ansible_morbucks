# Runbook: deploy an Elixir app to the morbucks server

When asked to "deploy / push Elixir app **X** to morbucks under domain **Y**",
follow this. morbucks is an all-in-one box (Caddy auto-TLS + PostgreSQL + build
& deploy tooling). Provisioning runs from a workstation; **build/deploy run ON
morbucks** (`connection: local`). Worked reference: `machteldbakker_nl`
(`app_vars/machteldbakker_nl.yml` + its `rel/overlays/config.exs.j2`).

morbucks public IP: **217.160.42.57**. Repos here are **public** → app_vars must
stay secret-free.

## Phase A — prepare the app repo (one-time per app)

Model these on koopmans_transportportal / machteldbakker_nl:

1. **`mix.exs`** — add a release with a runtime config provider:
   ```elixir
   releases: [
     APP: [
       include_executables_for: [:unix],
       applications: [runtime_tools: :permanent],
       validate_compile_env: false,
       config_providers: [{Config.Reader, {:system, "RELEASE_ROOT", "/config.exs"}}]
     ]
   ]
   ```
2. **`rel/overlays/config.exs.j2`** — runtime config as a bare keyword list
   `[app: [{Repo, [...]}, {Endpoint, [...]}, {Mailer, [...]}, {:key, val}]]`.
   Placeholders are Jinja vars from app_vars + the deploy role: `database_host`,
   `database_port`, `database_name`, `database_user`, `database_password`,
   `http_port` (bind `ip: {127,0,0,1}`), `public_host`, `secret_key_base`,
   `admin_password`, `mail_relay`/`mail_port`/`mail_from_email`.
3. **`config/prod.exs`** — `server: true`, `check_origin: false`,
   `cache_static_manifest`. **Delete `config/runtime.exs`** (or make sure it does
   not `raise` on missing env vars — the provider supplies config instead).
4. **`.tool-versions`** present (e.g. `erlang 28.4.2` / `elixir 1.19.5-otp-28`).
5. Sending mail? add `{:gen_smtp, "~> 1.3"}` and point the Swoosh SMTP mailer at
   `127.0.0.1:25` (the local relay). Run `mix deps.get` to update mix.lock.
6. Design assets (headers, logos) belong in **`priv/static/...`**, not derived
   from uploaded DB content, or they'll be blank on a fresh prod DB.
7. Validate before deploying: render `config.exs.j2` with sample vars and check
   with `elixir -e 'Config.Reader.read!("config.exs")'`.
8. Commit, `git tag <version>`, push the branch **and** the tag.

## Phase B — wire it into morbucks and deploy

1. **`app_vars/<app>.yml`** (secret-free; copy `example_app.yml.example`):
   `repo:` = **https://** URL if the repo is public (keyless clone), else the
   `git@` URL + a deploy key for the `deploy` user. Set `domain`, `public_host`,
   a **unique** `http_port`, `database: true`, `database_host: 127.0.0.1`,
   `database_port: 5432`, and `mail_*`. Do NOT put DB passwords / secret_key_base
   / admin password here — the deploy role derives DB creds as `<app>_<env>` and
   generates+persists the rest under `/opt/elixir_releases/.secrets/<env>/<app>/`.
2. Commit + push `app_vars/<app>.yml` (public-safe).
3. **Point DNS** for the domain at 217.160.42.57 *before* deploying, or Caddy's
   ACME cert will fail. For testing without DNS, set `caddy_global_extra` to the
   LE staging endpoint in `group_vars/all/main.yml`.
4. On morbucks:
   ```
   git -C /opt/ansible_morbucks pull
   ./build.sh  <app> <tag>        # asdf installs erlang/elixir (Erlang compiles from source, slow first time)
   ./deploy.sh <app> <tag> prod
   ```
5. Verify externally: `curl -I https://<domain>/` → HTTP 200 with a valid LE cert;
   `systemctl is-active <app>_prod` on the box. The admin password is printed at
   the end of the deploy and stored in the secrets dir.

## Gotchas

- app_vars must be **secret-free** (public repos).
- Give every app a **unique `http_port`** (machteldbakker_nl uses 4070).
- `./deploy.sh` restarts the service on every artifact extraction (a code-only
  deploy still restarts).
- Don't parse `.tool-versions` in a templated var — the build uses `asdf install`.
- Old `lib/<app>-<vsn>` dirs accumulate under the release dir; harmless.
