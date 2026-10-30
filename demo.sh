#!/usr/bin/env bash
# Runs one walkthrough step inside the vault-demo container.
#
#   ./demo.sh 1        tour of the namespace tree
#   ./demo.sh 2        shared auth, inherited by the children
#   ./demo.sh 3        finance/ is a separate tenant
#   ./demo.sh 4        cross-namespace permissions
#   ./demo.sh all      every step, in order
#   PAUSE=0 ./demo.sh all   no prompts between sections
#
# Set CONTAINER_CLI=docker to use Docker instead of Podman.
set -euo pipefail

CLI="${CONTAINER_CLI:-podman}"
NAME="vault-demo"

if ! "${CLI}" exec "${NAME}" test -f /vault/data/demo.env 2>/dev/null; then
  echo "Container ${NAME} is not running or has not finished provisioning." >&2
  echo "Start it with: ${CLI} compose up -d --build   then watch: ${CLI} compose logs -f vault" >&2
  exit 1
fi

run_step() {
  local script
  script=$("${CLI}" exec "${NAME}" sh -c "ls /vault/scripts/demo/0$1-*.sh")
  "${CLI}" exec -it -e PAUSE="${PAUSE:-1}" "${NAME}" bash "${script}"
}

case "${1:-}" in
  1|2|3|4) run_step "$1" ;;
  all)     for n in 1 2 3 4; do run_step "$n"; done ;;
  *)       sed -n '2,10p' "$0"; exit 1 ;;
esac
