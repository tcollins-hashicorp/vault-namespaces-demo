#!/usr/bin/env bash
# Shared helpers for the walkthrough scripts. Sourced, not executed.
# Runs inside the vault-demo container.

export VAULT_ADDR="http://127.0.0.1:8200"
ROOT_TOKEN=$(cat /vault/data/.root_token)
export ROOT_TOKEN
# shellcheck disable=SC1091
source /vault/data/demo.env

PAUSE="${PAUSE:-1}"   # PAUSE=0 ./demo.sh N runs a script without stopping

C_HEAD="\033[1;37;45m"; C_CMD="\033[1;33m"; C_NOTE="\033[0;36m"; C_OK="\033[1;32m"; C_DENY="\033[1;31m"; C_OFF="\033[0m"

banner() { echo; echo -e "${C_HEAD} $* ${C_OFF}"; echo; }
note()   { echo -e "${C_NOTE}# $*${C_OFF}"; }
pause()  { [ "${PAUSE}" = "1" ] && read -r -p "$(echo -e "${C_NOTE}[enter to continue]${C_OFF}")" _ || true; echo; }

# say <token> <namespace> -- <vault args...>
# Prints the command the audience should read, then runs it as that token in
# that namespace. Exit status is reported rather than fatal, so a 403 is a
# demo result and not a crash.
say() {
  local token="$1" ns="$2"; shift 2; [ "$1" = "--" ] && shift
  local who="${token:0:7}"
  case "${token}" in
    "${ROOT_TOKEN}") who="root" ;;
    "${ALICE_TOKEN:-x}") who="alice" ;;
    "${BOB_TOKEN:-x}") who="bob" ;;
    "${CAROL_TOKEN:-x}") who="carol" ;;
    "${FRANK_TOKEN:-x}") who="frank" ;;
  esac
  echo -e "${C_CMD}[${who} @ ${ns:-root}] \$ vault $*${C_OFF}"
  if VAULT_TOKEN="${token}" VAULT_NAMESPACE="${ns}" vault "$@"; then
    echo -e "${C_OK}  -> allowed${C_OFF}"
  else
    echo -e "${C_DENY}  -> denied (exit $?)${C_OFF}"
  fi
  echo
}

# login <namespace> <username>  -> prints a token
login() {
  VAULT_TOKEN="${ROOT_TOKEN}" vault write -namespace="$1" -field=token \
    "auth/userpass/login/$2" password="${DEMO_PASSWORD}"
}
