#!/usr/bin/env bash
# =============================================================================
# 20-namespaces.sh — Vault Enterprise namespaces demo
#
# Builds this tree on first init (VAULT_ADDR and a root VAULT_TOKEN are already
# exported by the entrypoint):
#
#   root
#   ├── platform/                 shared login point: userpass, entities
#   │   ├── team-a/               KV + a group that grants alice access
#   │   └── team-b/               KV + a group that grants bob access
#   └── finance/                  fully separate: own userpass, own entities
#
# Credentials and IDs land in /vault/data/demo.env for the demo scripts.
# =============================================================================
set -euo pipefail

DEMO_ENV="/vault/data/demo.env"
PASSWORD="demo-password"

log() { echo -e "\033[1;35m[namespaces]\033[0m $*"; }

# ---------------------------------------------------------------------------
# 1. Namespaces
# ---------------------------------------------------------------------------
log "Creating namespaces..."
vault namespace create platform
vault namespace create -namespace=platform team-a
vault namespace create -namespace=platform team-b
vault namespace create finance

# ---------------------------------------------------------------------------
# 2. Shared auth in platform/
#    Enabled once, in the parent. Tokens issued here can be used in
#    platform/team-a and platform/team-b because child namespaces accept
#    tokens from their ancestors.
# ---------------------------------------------------------------------------
log "Enabling userpass in platform/..."
vault auth enable -namespace=platform userpass
PLATFORM_ACCESSOR=$(vault auth list -namespace=platform -format=json | jq -r '."userpass/".accessor')

for user in alice bob carol; do
  vault write -namespace=platform "auth/userpass/users/${user}" password="${PASSWORD}" token_ttl=1h token_max_ttl=4h
done

# carol is the platform admin. Her policy lives in platform/ and reaches into
# the children by path prefix: team-a/... and team-b/... are relative to
# platform/ from this policy's point of view.
vault policy write -namespace=platform platform-admin - <<'EOF'
# Manage the platform namespace itself
path "sys/namespaces/*"        { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "sys/policies/acl/*"      { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/mounts/*"            { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/mounts"              { capabilities = ["read"] }
path "identity/*"              { capabilities = ["create", "read", "update", "delete", "list"] }
path "auth/*"                  { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }

# Reach into the child namespaces by prefix. These paths are evaluated
# relative to platform/, so "team-a/secret/data/*" means
# platform/team-a/secret/data/*.
path "team-a/*"                { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
path "team-b/*"                { capabilities = ["create", "read", "update", "delete", "list", "sudo"] }
EOF

# ---------------------------------------------------------------------------
# 3. Identity in platform/
#    Entities live in the parent so that groups in the children can reference
#    them. A group may contain entities from its own namespace or any ancestor.
# ---------------------------------------------------------------------------
log "Creating entities in platform/..."
mk_entity() {
  local name="$1" policies="${2:-}"
  local id
  if [ -n "${policies}" ]; then
    id=$(vault write -namespace=platform -format=json identity/entity name="${name}" policies="${policies}" | jq -r '.data.id')
  else
    id=$(vault write -namespace=platform -format=json identity/entity name="${name}" | jq -r '.data.id')
  fi
  vault write -namespace=platform identity/entity-alias name="${name}" canonical_id="${id}" mount_accessor="${PLATFORM_ACCESSOR}" > /dev/null
  echo "${id}"
}

ALICE_ID=$(mk_entity alice)
BOB_ID=$(mk_entity bob)
CAROL_ID=$(mk_entity carol platform-admin)

# ---------------------------------------------------------------------------
# 4. Child namespaces: KV, a policy and a group each
#    The policy is written in the child, so the child's own admin can change it
#    later without touching platform/. The group pulls the entity in from the
#    parent. That is what "inheriting authentication" looks like in Vault.
# ---------------------------------------------------------------------------
provision_team() {
  local team="$1" entity_id="$2" owner="$3"
  local ns="platform/${team}"
  log "Provisioning ${ns}..."

  vault secrets enable -namespace="${ns}" -path=secret kv-v2
  vault kv put -namespace="${ns}" secret/app/config \
    owner="${owner}" \
    db_password="$(openssl rand -hex 12)" \
    api_key="${team}_$(openssl rand -hex 8)"
  vault kv put -namespace="${ns}" secret/shared/handbook \
    wiki="https://wiki.example.internal/${team}" \
    on_call="${owner}"

  vault policy write -namespace="${ns}" "${team}-kv" - <<EOF
path "secret/data/*"     { capabilities = ["create", "read", "update", "delete", "list"] }
path "secret/metadata/*" { capabilities = ["read", "list", "delete"] }
EOF

  vault write -namespace="${ns}" identity/group \
    name="${team}-devs" \
    policies="${team}-kv" \
    member_entity_ids="${entity_id}" > /dev/null
}

provision_team team-a "${ALICE_ID}" alice
provision_team team-b "${BOB_ID}" bob

# ---------------------------------------------------------------------------
# 5. finance/ — nothing shared with platform/
#    Its own userpass, its own entity, its own KV. A platform token cannot be
#    used here and a finance token cannot be used in platform/.
# ---------------------------------------------------------------------------
log "Provisioning finance/ as a separate tenant..."
vault auth enable -namespace=finance userpass
FINANCE_ACCESSOR=$(vault auth list -namespace=finance -format=json | jq -r '."userpass/".accessor')

vault write -namespace=finance auth/userpass/users/frank password="${PASSWORD}" token_ttl=1h

vault secrets enable -namespace=finance -path=secret kv-v2
vault kv put -namespace=finance secret/ledger/q4 \
  revenue="4,200,000" \
  audit_contact="frank" \
  bank_token="fin_$(openssl rand -hex 10)"

vault policy write -namespace=finance finance-kv - <<'EOF'
path "secret/data/*"     { capabilities = ["create", "read", "update", "delete", "list"] }
path "secret/metadata/*" { capabilities = ["read", "list", "delete"] }
EOF

FRANK_ID=$(vault write -namespace=finance -format=json identity/entity name="frank" | jq -r '.data.id')
vault write -namespace=finance identity/entity-alias name="frank" canonical_id="${FRANK_ID}" mount_accessor="${FINANCE_ACCESSOR}" > /dev/null

# Group with no members yet. Demo step 4 adds alice (from platform/) to show
# the non-hierarchical sharing switch.
vault write -namespace=finance identity/group \
  name="finance-readers" \
  policies="finance-kv" > /dev/null

# ---------------------------------------------------------------------------
# 6. Hand the IDs to the demo scripts
# ---------------------------------------------------------------------------
cat > "${DEMO_ENV}" <<EOF
DEMO_PASSWORD=${PASSWORD}
ALICE_ID=${ALICE_ID}
BOB_ID=${BOB_ID}
CAROL_ID=${CAROL_ID}
FRANK_ID=${FRANK_ID}
PLATFORM_ACCESSOR=${PLATFORM_ACCESSOR}
FINANCE_ACCESSOR=${FINANCE_ACCESSOR}
EOF
chmod 600 "${DEMO_ENV}"

log "Done. Users alice, bob, carol (platform/) and frank (finance/) share the password '${PASSWORD}'."
