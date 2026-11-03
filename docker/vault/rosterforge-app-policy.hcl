# Least privilege for the app: read its own secrets, nothing else.
path "secret/data/rosterforge" {
  capabilities = ["read"]
}

path "secret/data/rosterforge/*" {
  capabilities = ["read"]
}
