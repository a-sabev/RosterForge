# Single-node Vault server with integrated (Raft) storage, persisted in the vault-data volume.

storage "raft" {
  path    = "/vault/file"
  node_id = "rosterforge-vault-1"
}

# TLS is off because the listener is only reachable on the compose network and on
# 127.0.0.1 (see compose.yaml). Any non-local deployment must enable TLS here.
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

# HashiCorp's recommendation for integrated storage; also needed under rootless Podman.
disable_mlock = true
ui            = false
