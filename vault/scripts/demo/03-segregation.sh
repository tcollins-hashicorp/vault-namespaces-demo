#!/usr/bin/env bash
# Step 3 — finance/ shares nothing with platform/
source /vault/scripts/demo/00-lib.sh

ALICE_TOKEN=$(login platform alice); export ALICE_TOKEN
FRANK_TOKEN=$(login finance frank); export FRANK_TOKEN

banner "3. A platform token is useless in finance/"
note "finance/ is not under platform/, so Vault will not even look the token up."
say "${ALICE_TOKEN}" "finance" -- kv get secret/ledger/q4
say "${ALICE_TOKEN}" "finance" -- token lookup
pause

banner "finance/ has its own login, its own identity store"
say "${FRANK_TOKEN}" "finance" -- token lookup -format=json
say "${FRANK_TOKEN}" "finance" -- kv get secret/ledger/q4
pause

banner "And frank gets nowhere in platform/"
say "${FRANK_TOKEN}" "platform" -- kv list secret/
say "${FRANK_TOKEN}" "platform/team-a" -- kv get secret/app/config
say "${FRANK_TOKEN}" "" -- namespace list
pause

banner "Who can see both? Only the root namespace"
note "Every namespace descends from root, so a root-namespace token with the"
note "right policy reaches all of them. That is the trade-off: isolation"
note "between tenants, but a single operator namespace above them all."
say "${ROOT_TOKEN}" "finance" -- kv get secret/ledger/q4
say "${ROOT_TOKEN}" "platform/team-b" -- kv get secret/app/config
pause

banner "Separate tenants on one cluster"
note "finance/ and platform/ share hardware, storage, the unseal keys, the"
note "licence and the audit devices. They share no auth, no policies and no"
note "identities. Change either one and the other does not notice."
