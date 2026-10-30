#!/usr/bin/env bash
# Step 2 — one login point in platform/, access decided in the children
source /vault/scripts/demo/00-lib.sh

banner "2. alice logs in once, at platform/"
note "There is no userpass mount in team-a. alice authenticates against the"
note "parent and gets a token whose home namespace is platform/."
echo -e "${C_CMD}[alice] \$ vault write -namespace=platform auth/userpass/login/alice password=...${C_OFF}"
ALICE_TOKEN=$(login platform alice); export ALICE_TOKEN
echo "token: ${ALICE_TOKEN:0:12}..."
echo
say "${ALICE_TOKEN}" "platform" -- token lookup -format=json
note "policies: only default. The group policy appears later, under"
note "external_namespace_policies, once alice makes a request in team-a."
pause

banner "The same token works in platform/team-a"
note "Child namespaces accept tokens issued by an ancestor. The team-a-devs"
note "group matches alice's entity and adds team-a-kv for this request."
say "${ALICE_TOKEN}" "platform/team-a" -- kv get secret/app/config
say "${ALICE_TOKEN}" "platform/team-a" -- kv put secret/app/notes note="written by alice $(date +%T)"
say "${ALICE_TOKEN}" "platform/team-a" -- token lookup -format=json
pause

banner "...but not in platform/team-b"
note "Same token, sibling namespace. team-b's group does not list alice."
say "${ALICE_TOKEN}" "platform/team-b" -- kv get secret/app/config
pause

banner "The other way round: a parent policy reaching down by path"
note "carol holds platform-admin, written in platform/. It contains"
note "  path \"team-a/*\" and path \"team-b/*\""
note "which Vault reads relative to platform/. No group in the children."
CAROL_TOKEN=$(login platform carol); export CAROL_TOKEN
say "${CAROL_TOKEN}" "platform/team-a" -- kv get secret/shared/handbook
say "${CAROL_TOKEN}" "platform/team-b" -- kv get secret/shared/handbook
say "${CAROL_TOKEN}" "platform" -- namespace list
pause

banner "Two ways to inherit, two owners"
note "Group in the child  -> the child's admin decides who gets in (alice)."
note "Policy in the parent -> the platform team decides, by path prefix (carol)."
note "Neither needs an auth method in the child."
