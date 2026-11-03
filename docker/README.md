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

## How Vault unseals and the app gets its secrets

### What `vault-bootstrap` is

A one-shot container that does the job a human Vault operator would do: initialize Vault,
unseal it after every restart, and set up the policy and login the app needs. It uses the
same `hashicorp/vault` image, but only for the `vault` command-line tool. It runs
`vault/bootstrap.sh` against the real Vault server at `http://vault:8200`, then exits.
The app waits for it to finish (`service_completed_successfully`).

It's the only service that mounts the `vault-keys` volume, so it's the only one that can
read the unseal key and root token.

### Three keys, each locking the next

```
unseal key       ← in vault-keys/init.txt. Vault never stores it.
   locks ▼
root key         ← stored encrypted in vault-data
   locks ▼
encryption key   ← stored encrypted in vault-data
   locks ▼
your secrets     ← stored encrypted in vault-data
```

The layers let each key change without touching the others. The encryption key can be
rotated without re-encrypting everything, and the unseal key can be replaced
(`vault operator rekey`), split into shares, or handed to a cloud KMS without touching the
data.

### The flow

Vault always starts **sealed**: it has its data but can't decrypt it. `vault-bootstrap`
asks Vault whether it is initialized.

- **First start only (init):** Vault isn't initialized, so the bootstrap runs
  `vault operator init`. Vault generates the three keys and stores the encrypted root key
  and encryption key in `vault-data`. It returns the unseal key and root token **once**,
  and the bootstrap saves them right away to `init.txt` on the `vault-keys` volume. Init
  doesn't unseal Vault; that's the next step.
- **Every start (unseal):** the bootstrap reads the unseal key from `init.txt` and sends it
  to Vault (`PUT /v1/sys/unseal`). Vault uses it to decrypt the root key, which decrypts
  the encryption key. It keeps those in memory and forgets the unseal key. The bootstrap
  then (re)applies the policy, AppRole and `secret/rosterforge`, and exits.

**Only then does the app start:**

```
1. app ── POST /v1/auth/approle/login {role_id, secret_id} ──► vault
   app ◄── token (policy rosterforge-app, 1h, renewable up to 24h) ──

2. app ── GET /v1/secret/data/rosterforge   X-Vault-Token: <token> ──► vault
         vault checks the token's policy allows this path,
         decrypts the secret with the encryption key in memory
   app ◄── spring.datasource.username / spring.datasource.password ──

3. app ── username + password ──► postgres (role rosterforge)
```

The token is permission, not a key. Vault does the decrypting, and only if the policy
allows the path; any other path, or no token, gets `403 Forbidden`. The app never sees any
key, and the unseal key plays no part after unsealing.

When Vault restarts, its memory is wiped and it's sealed again. The next `compose up`
repeats the unseal step.

### Where the unseal key lives

```
Windows
 └─ Podman VM (podman-machine-default)
     └─ /var/lib/containers/storage/volumes/rosterforge_vault-keys/_data/init.txt
```

It's not on the Windows drive or in the repo. Only `vault-bootstrap` mounts it, at
`/vault-keys`. It survives restarts, reboots and `down` without `-v`. It's deleted by
`down -v`, `podman volume rm`, or `podman machine rm`/`reset`. Vault shows the key only
once, at init, so if `init.txt` is lost while `vault-data` still exists, Vault can never be
unsealed again.

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
