#!/usr/bin/env bash
# Step 1 — what the environment looks like
source /vault/scripts/demo/00-lib.sh

banner "1. The namespace tree"
note "Four namespaces. platform/ holds two children; finance/ stands alone."
say "${ROOT_TOKEN}" "" -- namespace list
say "${ROOT_TOKEN}" "platform" -- namespace list
pause

banner "Each namespace is its own small Vault"
note "Auth methods are mounted per namespace. platform/ and finance/ each have"
note "a userpass mount; the children have none of their own."
say "${ROOT_TOKEN}" "platform" -- auth list
say "${ROOT_TOKEN}" "platform/team-a" -- auth list
say "${ROOT_TOKEN}" "finance" -- auth list
pause

banner "Policies and identity are per namespace too"
say "${ROOT_TOKEN}" "platform" -- policy list
say "${ROOT_TOKEN}" "platform/team-a" -- policy list
say "${ROOT_TOKEN}" "platform/team-a" -- read identity/group/name/team-a-devs
note "The group lives in platform/team-a but its member entity (alice) lives in"
note "platform/. That link is what the next step relies on."
pause

banner "Same thing in the UI"
note "Open http://localhost:8200 and use the namespace picker (top left), or"
note "http://localhost:8200/ui/vault/secrets?namespace=platform%2Fteam-a"
note "Root token: ${ROOT_TOKEN}"
