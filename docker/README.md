# Local infra

`docker-compose.yaml` starts local dev infra on non-default ports (to avoid clashing
with other projects on this machine):

| Service  | Port | Notes                              |
|----------|------|-------------------------------------|
| Postgres | 5434 | Event store + read-model projections |
| Kafka    | 9094 | Event backbone                       |
| Vault    | 8200 | Dev-mode container, root token locally |
| App      | 8080 | Only with `--profile app` (override with `APP_PORT`) |

Infra only (run the app from your IDE):
```
docker compose -f docker/docker-compose.yaml up -d
```

Full stack on any machine with Docker (no local Java/Maven needed):
```
docker compose -f docker/docker-compose.yaml --profile app up -d --build
```

Vault runs in dev mode, so its storage is in memory and is wiped on every restart.
The `vault-init` service writes the datasource credentials to `secret/rosterforge`
each time the stack starts. Postgres credentials default to `rosterforge`/`rosterforge`
and can be overridden with `POSTGRES_USER` / `POSTGRES_PASSWORD` in a `.env` file
next to the compose file.
