#!/usr/bin/env bash
# Step 4 — granting access across namespaces
source /vault/scripts/demo/00-lib.sh

ALICE_TOKEN=$(login platform alice); export ALICE_TOKEN
root() { VAULT_TOKEN="${ROOT_TOKEN}" vault "$@"; }

cleanup() {
  echo; note "cleanup: restoring the original group memberships and mode"
  root write -namespace=platform/team-b identity/group/name/team-b-devs \
    member_entity_ids="${BOB_ID}" > /dev/null || true
  root write -namespace=finance identity/group/name/finance-readers \
    member_entity_ids="" > /dev/null || true
  root write sys/config/group-policy-application \
    group_policy_application_mode="within_namespace_hierarchy" > /dev/null || true
}
trap cleanup EXIT

banner "4a. Inside the hierarchy: add alice to team-b's group"
note "team-b's admin can grant alice access without touching platform/ at all,"
note "because alice's entity sits in an ancestor namespace."
say "${ALICE_TOKEN}" "platform/team-b" -- kv get secret/shared/handbook
say "${ROOT_TOKEN}" "platform/team-b" -- write identity/group/name/team-b-devs \
  member_entity_ids="${BOB_ID},${ALICE_ID}"
say "${ALICE_TOKEN}" "platform/team-b" -- kv get secret/shared/handbook
note "Same token as before. No re-login. Vault re-evaluates group membership on"
note "every request."
pause

banner "What the token sees now"
say "${ALICE_TOKEN}" "platform/team-b" -- token lookup -format=json
note "external_namespace_policies lists team-b-kv under platform/team-b/."
pause

banner "4b. Across unrelated namespaces: finance/ wants to let alice in"
note "finance/ is not an ancestor or descendant of platform/. By default group"
note "policies only apply within a namespace hierarchy, so this is off."
say "${ROOT_TOKEN}" "" -- read sys/config/group-policy-application
pause

banner "Flip the global switch, then add alice to finance-readers"
note "group_policy_application_mode=any is cluster-wide. Every group in every"
note "namespace may now carry policies for members from anywhere."
say "${ROOT_TOKEN}" "" -- write sys/config/group-policy-application \
  group_policy_application_mode=any
say "${ROOT_TOKEN}" "finance" -- write identity/group/name/finance-readers \
  member_entity_ids="${ALICE_ID}"
say "${ALICE_TOKEN}" "finance" -- kv get secret/ledger/q4
pause

banner "Put the switch back and the access goes with it"
say "${ROOT_TOKEN}" "" -- write sys/config/group-policy-application \
  group_policy_application_mode=within_namespace_hierarchy
say "${ALICE_TOKEN}" "finance" -- kv get secret/ledger/q4
pause

banner "Three ways to cross a namespace boundary"
note "1. Policy in a parent, paths prefixed with the child name (carol)."
note "2. Group in the target namespace, entity from an ancestor (alice -> team-b)."
note "3. Group in any namespace + group_policy_application_mode=any (alice -> finance)."
note "Option 3 is a global setting. Decide it once, as a platform, and write it down."
