#!/bin/sh
# Brings Vault from any state (never initialized, sealed, or ready) to ready, then
# (re)applies everything the app needs. Runs on every `compose up`, so each step is
# idempotent.
set -eu

KEYS=/vault-keys/init.txt
ROLE=rosterforge-app

vault_status() { vault status -format=json 2>/dev/null || true; }

# --- Initialize (first start on this machine only) -------------------------------------
if ! vault_status | grep -q '"initialized": true'; then
  echo "vault-bootstrap: initializing Vault"
  umask 077
  vault operator init -key-shares=1 -key-threshold=1 > "$KEYS"
elif [ ! -s "$KEYS" ]; then
  echo "vault-bootstrap: Vault is initialized but its keys are missing from the vault-keys" >&2
  echo "volume, so it can never be unsealed. Reset the stack with 'down -v'." >&2
  exit 1
fi

UNSEAL_KEY=$(sed -n 's/^Unseal Key 1: //p' "$KEYS")
VAULT_TOKEN=$(sed -n 's/^Initial Root Token: //p' "$KEYS")
export VAULT_TOKEN

# --- Unseal (every start: Vault always restarts sealed) --------------------------------
if vault_status | grep -q '"sealed": true'; then
  echo "vault-bootstrap: unsealing"
  # `vault operator unseal` only takes the key as an argument or a TTY prompt; `write`
  # reads `-` from stdin, keeping the key out of argv.
  printf '%s' "$UNSEAL_KEY" | vault write sys/unseal key=- > /dev/null
fi

# Raft needs a moment after unsealing to elect itself leader before it accepts writes.
until wget -q -O /dev/null "$VAULT_ADDR/v1/sys/health" 2>/dev/null; do sleep 1; done

# --- Engines, policy, AppRole ----------------------------------------------------------
vault secrets list -format=json | grep -q '"secret/"' \
  || vault secrets enable -path=secret -version=2 kv
vault auth list -format=json | grep -q '"approle/"' \
  || vault auth enable approle

vault policy write "$ROLE" /scripts/rosterforge-app-policy.hcl > /dev/null

# secret_id_ttl=0 keeps the IDE login working across restarts; see README security model.
vault write "auth/approle/role/$ROLE" \
  token_policies="$ROLE" token_ttl=1h token_max_ttl=24h \
  secret_id_ttl=0 secret_id_num_uses=0 > /dev/null

# --- App secrets -----------------------------------------------------------------------
# @file makes the CLI read the value from disk, so the password never appears in argv.
vault kv put secret/rosterforge \
  spring.datasource.username=rosterforge \
  spring.datasource.password=@/run/secrets/postgres/app_password > /dev/null

# --- AppRole credentials for the app ---------------------------------------------------
# File names are Spring property names: the app imports these with configtree.
ROLE_ID_FILE=spring.cloud.vault.app-role.role-id
SECRET_ID_FILE=spring.cloud.vault.app-role.secret-id
CANONICAL=/out/container

secret_id_valid() {
  [ -s "$CANONICAL/$SECRET_ID_FILE" ] \
    && vault write -format=json "auth/approle/role/$ROLE/secret-id/lookup" \
         secret_id=@"$CANONICAL/$SECRET_ID_FILE" 2>/dev/null | grep -q '"secret_id_accessor"'
}

umask 077
vault read -field=role_id "auth/approle/role/$ROLE/role-id" > "$CANONICAL/$ROLE_ID_FILE"
if ! secret_id_valid; then
  echo "vault-bootstrap: issuing a new AppRole secret-id"
  vault write -f -field=secret_id "auth/approle/role/$ROLE/secret-id" > "$CANONICAL/$SECRET_ID_FILE"
fi

# The app image runs as uid 10001.
chown -R 10001:10001 "$CANONICAL"
chmod 0700 "$CANONICAL"
chmod 0400 "$CANONICAL"/*

# Host copy for IDE runs, owned by whoever owns the checked-out directory. chown can
# fail on Windows host mounts, where ownership doesn't apply anyway.
HOST_OWNER=$(stat -c '%u:%g' /out/host)
for f in "$ROLE_ID_FILE" "$SECRET_ID_FILE"; do
  cp "$CANONICAL/$f" "/out/host/$f"
  chown "$HOST_OWNER" "/out/host/$f" 2>/dev/null || true
  chmod 0600 "/out/host/$f"
done

echo "vault-bootstrap: ready"
