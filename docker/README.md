# Local infra

`docker-compose.yaml` starts local dev infra on non-default ports (to avoid clashing
with other projects on this machine):

| Service  | Port | Notes                              |
|----------|------|-------------------------------------|
| Postgres | 5434 | Event store + read-model projections |
| Kafka    | 9094 | Event backbone                       |
| Vault    | 8200 | Dev-mode container, root token locally |

Start with:
```
docker compose -f docker/docker-compose.yaml up -d
```
