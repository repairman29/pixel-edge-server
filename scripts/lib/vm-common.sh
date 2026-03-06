#!/usr/bin/env bash
# vm-common.sh — Shared connection helpers for all setup-*.sh scripts
#
# Source this from any setup script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/vm-common.sh"
#
# Then use:
#   vm_ssh "command to run on VM"
#   vm_scp local_file1 local_file2 remote_dest
#   vm_ssh_heredoc <<'REMOTE' ... REMOTE
#
# Override with environment variables or positional arg:
#   VM_HOST=droid@10.1.10.29 VM_PORT=8022 bash scripts/setup-foo.sh
#   bash scripts/setup-foo.sh droid@127.0.0.1

# Allow the first positional arg of the calling script to override VM_HOST
VM_HOST="${VM_HOST:-${1:-droid@100.78.73.64}}"
VM_PORT="${VM_PORT:-8022}"

# Connection commands (reusable across all setup scripts)
vm_ssh() {
  ssh -p "${VM_PORT}" -o ConnectTimeout=15 "${VM_HOST}" "$@"
}

vm_scp() {
  # Usage: vm_scp file1 file2 ... remote_dest
  # Last arg is the remote destination (will be prefixed with VM_HOST:)
  local args=("$@")
  local dest="${args[-1]}"
  local files=("${args[@]:0:$((${#args[@]}-1))}")
  scp -P "${VM_PORT}" "${files[@]}" "${VM_HOST}:${dest}"
}

vm_ssh_heredoc() {
  # Pipe a heredoc to bash on the VM
  ssh -p "${VM_PORT}" -o ConnectTimeout=15 "${VM_HOST}" bash -s
}

vm_banner() {
  local title="$1"
  local w=${#title}
  (( w += 6 ))
  echo "╔$(printf '═%.0s' $(seq 1 $w))╗"
  echo "║   ${title}   ║"
  echo "╚$(printf '═%.0s' $(seq 1 $w))╝"
  echo "  Target : ${VM_HOST}:${VM_PORT}"
  echo ""
}
