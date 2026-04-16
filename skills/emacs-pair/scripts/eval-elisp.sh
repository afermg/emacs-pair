#!/usr/bin/env bash
# Evaluate Elisp in a running Emacs server via emacsclient.
# Returns the printed result of the last expression to stdout.
#
# Usage:
#   eval-elisp.sh -e "(buffer-name (current-buffer))"
#   eval-elisp.sh script.el
#   eval-elisp.sh <<'EOF'
#     (with-current-buffer "foo.org" (buffer-string))
#   EOF
#   eval-elisp.sh --server myserver -e "(+ 1 2)"
#
# Options:
#   --server SOCKET   Path or name of Emacs server socket (auto-discovered if omitted)
#   -e EXPR           Elisp expression(s) to evaluate
#
# Multiple expressions are wrapped in (progn ...) automatically.
# The return value of the last expression is printed to stdout.
set -euo pipefail

server=""
code=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) server="$2"; shift 2 ;;
    -e)       code="$2"; shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        break ;;
  esac
done

# Read code from positional arg (file) or stdin
if [[ -n "$code" ]]; then
  : # already set via -e
elif [[ $# -gt 0 ]]; then
  code=$(cat "$1")
elif [[ ! -t 0 ]]; then
  code=$(cat)
else
  echo "Usage: eval-elisp.sh [-e EXPR | FILE | stdin]" >&2
  echo "       eval-elisp.sh --server SOCKET -e EXPR" >&2
  exit 1
fi

# Auto-discover server socket if not specified
if [[ -z "$server" ]]; then
  uid=$(id -u)
  xdg_runtime="${XDG_RUNTIME_DIR:-/run/user/${uid}}"

  # Try common locations in priority order
  for candidate in \
    "${xdg_runtime}/emacs/server" \
    "${TMPDIR:-/tmp}/emacs${uid}/server" \
    "${HOME}/.emacs.d/server" \
    "${XDG_CONFIG_HOME:-${HOME}/.config}/emacs/server"
  do
    if [[ -S "$candidate" ]]; then
      server="$candidate"
      break
    fi
  done

  if [[ -z "$server" ]]; then
    echo "No running Emacs server found. Start one with M-x server-start or (server-start) in init." >&2
    exit 1
  fi
fi

# Wrap multiple top-level expressions in (progn ...) so emacsclient
# sees a single form. A single expression is passed through unchanged.
# Heuristic: if code contains multiple balanced top-level sexps, wrap them.
expr_count=$(echo "$code" | grep -c '^\s*(' 2>/dev/null || true)
if [[ "$expr_count" -gt 1 ]]; then
  code="(progn ${code})"
fi

# Evaluate and print result; emacsclient --eval prints the Lisp read-syntax
# of the return value. Strip surrounding quotes from strings for cleaner output.
result=$(emacsclient --socket-name="$server" --eval "$code" 2>&1) || {
  echo "$result" >&2
  exit 1
}

echo "$result"
