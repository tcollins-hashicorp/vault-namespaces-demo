#!/usr/bin/env bash
# =============================================================================
# vault-entrypoint.sh — Vault Base Demo
#
# FIRST RUN (fresh volume):
#   1. Start Vault server in background
#   2. Init (1 key-share / threshold 1)
#   3. Unseal
#   4. Enable KV-v2, write sample secrets
#   5. Run any capability provisioning scripts in scripts/provision.d/
#   6. Mark as initialised
#
# SUBSEQUENT RUNS:
#   1. Start Vault server in background
#   2. Unseal using the saved key
#   3. Stay in foreground
# =============================================================================
set -euo pipefail

DATA_DIR="/vault/data"
UNSEAL_FILE="${DATA_DIR}/.unseal_key"
ROOT_TOKEN_FILE="${DATA_DIR}/.root_token"
INIT_FLAG="${DATA_DIR}/.initialized"
PROVISION_DIR="/vault/scripts/provision.d"

export VAULT_ADDR="http://127.0.0.1:8200"

mkdir -p "${DATA_DIR}"

log()  { echo -e "\033[1;36m[vault-init]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[vault-init]\033[0m $*"; }
warn() { echo -e "\033[1;33m[vault-init]\033[0m $*"; }

# ---------------------------------------------------------------------------
# Wait for the Vault API to respond (any HTTP response counts — sealed is fine)
# ---------------------------------------------------------------------------
wait_vault_up() {
  log "Waiting for Vault API..."
  for i in $(seq 1 60); do
    HTTP=$(curl -so /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || true)
    if [[ "${HTTP}" =~ ^(200|429|472|473|501|503)$ ]]; then
      ok "Vault API responding (HTTP ${HTTP})"
      return 0
    fi
    sleep 1
  done
  warn "Vault API did not respond within 60s — aborting."
  exit 1
}

# ---------------------------------------------------------------------------
# Wait for Vault to be active (HTTP 200 = initialised, unsealed, active)
# ---------------------------------------------------------------------------
wait_vault_active() {
  log "Waiting for Vault to be active..."
  for i in $(seq 1 30); do
    HTTP=$(curl -so /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || true)
    if [ "${HTTP}" = "200" ]; then
      ok "Vault is active."
      return 0
    fi
    sleep 1
  done
  warn "Vault did not become active within 30s."
  exit 1
}

# ---------------------------------------------------------------------------
# Start Vault server in the background
# ---------------------------------------------------------------------------
log "Starting Vault server..."
vault server -config=/vault/config/vault.hcl &
VAULT_PID=$!
wait_vault_up

# ---------------------------------------------------------------------------
# FIRST RUN — initialise, unseal, configure demo data
# ---------------------------------------------------------------------------
if [ ! -f "${INIT_FLAG}" ]; then
  log "=== First run: initialising Vault ==="

  INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

  UNSEAL_KEY=$(echo "${INIT_JSON}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
  ROOT_TOKEN=$(echo "${INIT_JSON}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['root_token'])")

  echo "${UNSEAL_KEY}"  > "${UNSEAL_FILE}"
  echo "${ROOT_TOKEN}"  > "${ROOT_TOKEN_FILE}"
  chmod 600 "${UNSEAL_FILE}" "${ROOT_TOKEN_FILE}"

  vault operator unseal "${UNSEAL_KEY}" > /dev/null
  wait_vault_active

  export VAULT_TOKEN="${ROOT_TOKEN}"

  # -- KV-v2 secrets engine ---------------------------------------------------
  log "Enabling KV-v2 at secret/..."
  vault secrets enable -path=secret kv-v2
  ok "KV-v2 enabled."

  # -- Sample secrets ---------------------------------------------------------
  log "Writing sample secrets..."
  vault kv put secret/db/credentials \
    username="vault_demo_user" \
    password="$(openssl rand -hex 16)" \
    host="db.example.internal" \
    port="5432" \
    database="appdb"

  vault kv put secret/api/keys \
    stripe_key="sk_test_demo_$(openssl rand -hex 8)" \
    sendgrid_key="SG.demo_$(openssl rand -hex 12)" \
    github_token="ghp_demo_$(openssl rand -hex 10)"

  vault kv put secret/ssh/hosts \
    bastion_host="bastion.example.internal" \
    bastion_user="ubuntu"

  vault kv put secret/app/config \
    log_level="info" \
    max_connections="100" \
    feature_flags="dark_mode,beta_api"

  ok "Sample secrets written."

  # -- Capability provisioning ------------------------------------------------
  # Each capability module drops a numbered *.sh file into provision.d/.
  # They run in filename order with VAULT_ADDR and VAULT_TOKEN (root) already
  # set, so a capability script can enable engines, write policies, etc.
  if compgen -G "${PROVISION_DIR}/*.sh" > /dev/null 2>&1; then
    log "Running capability provisioning scripts..."
    for script in "${PROVISION_DIR}"/*.sh; do
      log "  -> $(basename "${script}")"
      bash "${script}"
    done
    ok "Capability provisioning complete."
  fi

  touch "${INIT_FLAG}"
  ok "=== First-run complete ==="

# ---------------------------------------------------------------------------
# SUBSEQUENT RUNS — just unseal
# ---------------------------------------------------------------------------
else
  log "=== Existing data found — unsealing ==="

  if [ ! -f "${UNSEAL_FILE}" ]; then
    warn "Unseal key not found at ${UNSEAL_FILE} — cannot auto-unseal."
    warn "Unseal manually: docker exec vault-demo vault operator unseal <key>"
  else
    UNSEAL_KEY=$(cat "${UNSEAL_FILE}")
    vault operator unseal "${UNSEAL_KEY}" > /dev/null
    wait_vault_active
    ok "Vault unsealed."
  fi
fi

# ---------------------------------------------------------------------------
# Print access info
# ---------------------------------------------------------------------------
ROOT_TOKEN=$(cat "${ROOT_TOKEN_FILE}" 2>/dev/null || echo "(see ${ROOT_TOKEN_FILE})")

echo ""
echo -e "\033[1;32m╔══════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;32m║         Vault Demo — Ready.                                  ║\033[0m"
echo -e "\033[1;32m╚══════════════════════════════════════════════════════════════╝\033[0m"
echo -e "  Vault UI   :  http://localhost:8200"
echo -e "  Root token :  ${ROOT_TOKEN}"
echo -e ""
echo ""

# ---------------------------------------------------------------------------
# Stay in foreground
# ---------------------------------------------------------------------------
wait "${VAULT_PID}"
