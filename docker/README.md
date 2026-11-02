# Local infra

`compose.yaml` runs the local stack. Ports are non-default (to avoid clashing with other
projects on this machine) and bound to `127.0.0.1` only:

| Service  | Port | Notes                                                 |
|----------|------|-------------------------------------------------------|
| Postgres | 5434 | Event store + read-model projections                  |
| Kafka    | 9094 | Event backbone                                        |
| Vault    | 8200 | Server mode, persistent Raft storage                  |
| App      | 8080 | Only with `--profile app` (override with `APP_PORT`)  |

## New machine

Needs Git and a container runtime: Docker, or Podman with `docker-compose` (use
`podman compose` wherever this says `docker compose`). Nothing else: no Java, no
`.env`, no secrets to copy over.

```
git clone <repo-url> && cd RosterForge

# infra only, run the app from the IDE (working directory = repo root)
docker compose -f docker/compose.yaml up -d

# or the full stack, app included
docker compose -f docker/compose.yaml --profile app up -d --build
```

Run the same command again after a reboot. Vault always restarts sealed, and `up` re-runs
`vault-bootstrap`, which unseals it.

## What happens on start

1. `secrets-init` generates the Postgres superuser and app passwords. This happens on the
   first start only, into the `postgres-secrets` volume.
2. Postgres initializes, and `postgres/initdb/` creates the `rosterforge` role. It is not
   a superuser: it owns the `rosterforge` database and has no rights anywhere else.
3. `vault-bootstrap` initializes Vault on the first start, unseals it on every start, and
   (re)applies the `rosterforge-app` policy, the AppRole, and `secret/rosterforge`
   (the datasource credentials).
4. It then writes the app's AppRole `role-id`/`secret-id` to the `app-secrets` volume (for
   the container) and to `docker/.secrets/` (for IDE runs, gitignored). The app loads them
   through `configtree`, logs in to Vault, and reads its datasource credentials from there.

## Security model

What this setup guarantees:
- No secret is in git, in this compose file, or in any image. Each machine generates its
  own secrets.
- The app authenticates with a least-privilege AppRole that can read only
  `secret/rosterforge/*`, and it connects to Postgres as a non-superuser role.
- Secrets never pass through command-line arguments, so they don't show up in
  `docker inspect` or `ps`.
- Nothing is reachable from the local network.
- The app container runs as a non-root user with a read-only filesystem, no Linux
  capabilities, and `no-new-privileges`.

Known gaps, and what production would use instead:

| Here | Production |
|------|------------|
| The unseal key and root token sit in the `vault-keys` volume, next to Vault itself | Auto-unseal through a cloud KMS or HSM; root token revoked after setup |
| A single unseal key share | Shamir shares split between operators |
| No TLS (traffic stays on localhost and the compose network) | TLS on the Vault listener and on Postgres |
| The AppRole `secret-id` never expires, so IDE runs survive restarts | Short-lived, response-wrapped secret-ids delivered by the platform |
| A static Postgres password, generated per machine | Dynamic per-lease credentials from Vault's database secrets engine |
| Kafka uses PLAINTEXT with no authentication | SASL/SCRAM or mTLS, plus ACLs |

## Resetting

```
docker compose -f docker/compose.yaml --profile app down -v
```

This wipes all data and all secrets together. Never delete only some of the volumes: the
Postgres passwords must match the existing database, and Vault can't be unsealed without
the `vault-keys` volume. `vault-bootstrap` stops with an error if it detects that state.

Inspecting Vault as root from the host (the token is local to this machine):

```
docker run --rm -v rosterforge_vault-keys:/k:ro alpine cat /k/init.txt
```
