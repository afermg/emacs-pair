#!/usr/bin/env bash
# Open a URL in a browser via a (possibly remote) Emacs server.
#
# Use case: you're on a headless server with no GUI/browser, but your
# workstation does have a browser. Ask your workstation's Emacs to open the
# link by routing through its emacsclient over ssh.
#
# Usage:
#   browse-url.sh https://example.com                 # local Emacs
#   browse-url.sh --host workstation https://...      # remote Emacs over ssh
#   browse-url.sh --host workstation --server NAME URL
#
# Requires an Emacs server running on the target machine.
set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"
host_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)   host_args+=(--host "$2"); shift 2 ;;
    --server) host_args+=(--server "$2"); shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        break ;;
  esac
done

url="${1:-}"
if [[ -z "$url" ]]; then
  echo "Usage: browse-url.sh [--host HOST] [--server SOCKET] URL" >&2
  exit 1
fi

# Elisp string escapes: only " and \ are special inside a double-quoted string.
escaped=$(printf '%s' "$url" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

exec bash "$here/eval-elisp.sh" "${host_args[@]}" -e "(browse-url \"$escaped\")"
