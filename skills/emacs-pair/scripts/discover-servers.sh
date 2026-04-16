#!/usr/bin/env bash
# Discover running Emacs server sockets and report them as JSON.
# Checks standard socket locations and filters out dead sockets.
set -euo pipefail

uid=$(id -u)
results="[]"

# Collect candidate socket directories
candidates=()

# systemd/XDG runtime (most common on NixOS/systemd)
xdg_runtime="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
if [[ -d "${xdg_runtime}/emacs" ]]; then
  while IFS= read -r sock; do
    candidates+=("$sock")
  done < <(find "${xdg_runtime}/emacs" -maxdepth 1 -type s 2>/dev/null)
fi

# Legacy /tmp/emacs<uid>/
tmpdir="${TMPDIR:-/tmp}"
if [[ -d "${tmpdir}/emacs${uid}" ]]; then
  while IFS= read -r sock; do
    candidates+=("$sock")
  done < <(find "${tmpdir}/emacs${uid}" -maxdepth 1 -type s 2>/dev/null)
fi

# ~/.emacs.d/server (older default)
if [[ -S "${HOME}/.emacs.d/server" ]]; then
  candidates+=("${HOME}/.emacs.d/server")
fi

# ~/.config/emacs/server (XDG config path)
xdg_config="${XDG_CONFIG_HOME:-${HOME}/.config}"
if [[ -S "${xdg_config}/emacs/server" ]]; then
  candidates+=("${xdg_config}/emacs/server")
fi

for sock in "${candidates[@]}"; do
  [[ -S "$sock" ]] || continue

  name=$(basename "$sock")

  # Probe the socket — emacsclient exits 0 if server responds
  server_name=$( emacsclient --socket-name="$sock" --eval "(concat \"emacs-\" emacs-version)" 2>/dev/null ) || continue

  # emacsclient wraps strings in quotes; strip them
  server_name="${server_name//\"/}"

  entry=$(jq -n \
    --arg socket "$sock" \
    --arg name "$name" \
    --arg version "$server_name" \
    '{socket: $socket, name: $name, version: $version}')

  results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
done

echo "$results" | jq .
