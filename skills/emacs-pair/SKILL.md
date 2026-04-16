---
name: emacs-pair
description: >-
  Work inside a running Emacs session — read and write buffers, evaluate Elisp,
  run M-x commands, and inspect editor state. Use when the user wants you to
  interact with their live Emacs: read a buffer, modify text, run a command,
  configure something, or debug Elisp in their actual session.
allowed-tools: Bash(bash **/scripts/discover-servers.sh *), Bash(bash **/scripts/eval-elisp.sh *)
---

# Emacs Pair Programming Protocol

This skill gives you full access to a running Emacs session via `emacsclient`.
You can read buffers, insert and replace text, run M-x commands, evaluate
arbitrary Elisp, and inspect editor state — all without leaving the
conversation. The user sees the effects live in their Emacs.

## Philosophy

Emacs is a Lisp machine. Everything is a buffer, and everything is a function.
You have the full Elisp API available — `buffer-string`, `insert`, `save-buffer`,
`find-file`, `execute-kbd-macro`, `org-*`, `projectile-*`, anything. When in
doubt, reach for Elisp rather than trying to edit files on disk while Emacs has
them open.

- **Prefer Elisp over disk edits.** If Emacs has the file open, mutate the buffer
  through `eval-elisp.sh`, not the `Edit` tool. Disk edits bypass undo history,
  markers, overlays, and hooks.
- **Understand the buffer first.** Before modifying, read the relevant buffer
  content and understand its structure.
- **Be surgical.** Use `save-excursion` and `with-current-buffer` to avoid
  disturbing the user's cursor position or active buffer.
- **Communicate side effects.** If you run a command that moves point, changes
  the selection, or pops a window, tell the user.

## Prerequisites

The user must have an Emacs server running. They can start one with:
```
M-x server-start
```
or by adding `(server-start)` to their init file. On systemd systems, the
socket typically lives at `$XDG_RUNTIME_DIR/emacs/server`.

Named servers (started with `server-name` set) can be targeted with
`--server /path/to/socket`.

## Discovering the Server

```bash
bash scripts/discover-servers.sh
```

Returns a JSON array of live Emacs servers, each with `socket`, `name`, and
`version`. If empty, ask the user to run `M-x server-start`.

## Evaluating Elisp

```bash
# Single expression — result printed to stdout
bash scripts/eval-elisp.sh -e "(buffer-name (current-buffer))"

# Multiline — use a heredoc (prevents shell interpolation issues)
bash scripts/eval-elisp.sh <<'EOF'
(with-current-buffer "config.org"
  (buffer-string))
EOF

# From a file
bash scripts/eval-elisp.sh /tmp/my-script.el

# Target a specific server socket
bash scripts/eval-elisp.sh --server /run/user/1000/emacs/myserver -e "(+ 1 2)"
```

`emacsclient --eval` returns the Lisp read-syntax of the return value.
Strings come back quoted: `"hello"`. `nil` means no value or false. `t` means true.

## Common Operations

### Read the current buffer
```elisp
(with-current-buffer (current-buffer) (buffer-string))
```

### Read a specific buffer
```elisp
(with-current-buffer "config.org" (buffer-string))
```

### List open buffers
```elisp
(mapcar #'buffer-name (buffer-list))
```

### Get buffer file path
```elisp
(buffer-file-name (get-buffer "home-manager.nix"))
```

### Insert text at point (in current buffer)
```elisp
(insert "text to insert")
```

### Insert at a specific position without moving point
```elisp
(save-excursion
  (with-current-buffer "myfile.org"
    (goto-char (point-max))
    (insert "\n* New heading\n")))
```

### Replace buffer region
```elisp
(with-current-buffer "foo.el"
  (goto-char (point-min))
  (search-forward "old-text")
  (replace-match "new-text"))
```

### Save a buffer
```elisp
(with-current-buffer "config.org" (save-buffer))
```

### Open a file
```elisp
(find-file "/path/to/file.org")
```

### Run an M-x command
```elisp
(call-interactively #'org-agenda)
```

### Evaluate a region / defun
```elisp
(with-current-buffer "init.el"
  (eval-buffer))
```

### Get messages buffer (useful for debugging)
```elisp
(with-current-buffer "*Messages*"
  (buffer-string))
```

### Capture output from message/print
```elisp
(with-output-to-string
  (princ "hello")
  (print (+ 1 2)))
```

## Working with Org Mode

```elisp
;; Get agenda items
(org-agenda-list)

;; Insert a heading at end of file
(with-current-buffer "notes.org"
  (goto-char (point-max))
  (org-insert-heading)
  (insert "New task"))

;; Clock in on the item at point
(with-current-buffer "tasks.org"
  (org-clock-in))
```

## Multiline Elisp Tips

Shell quoting gets tricky with embedded strings. Always use a heredoc for
anything with quotes, backslashes, or multiple expressions:

```bash
bash scripts/eval-elisp.sh <<'EOF'
(let ((buf (get-buffer "config.org")))
  (when buf
    (with-current-buffer buf
      (goto-char (point-min))
      (re-search-forward "^\\* " nil t)
      (buffer-substring (line-beginning-position) (line-end-position)))))
EOF
```

The single-quoted `'EOF'` delimiter prevents the shell from interpolating `$`
variables or backticks inside the heredoc.

## Error Handling

If `eval-elisp.sh` exits non-zero, the error message from Emacs is on stderr.
Common causes:
- **`Symbol's value as variable is void`** — variable not defined in this session
- **`Wrong type argument`** — type mismatch; check assumptions about the buffer state
- **`No buffer named "..."`** — buffer not open; use `find-file` or `get-buffer-create`
- **Server not responding** — run `discover-servers.sh` to confirm the socket is live

## Guard Rails

- **Never write to a file on disk while Emacs has it open** — use `insert`/`save-buffer` instead
- **Avoid `kill-buffer` without asking** — it's destructive and loses unsaved changes
- **Don't run blocking commands** like `read-string` or `yes-or-no-p` interactively —
  they'll hang `emacsclient`. Use non-interactive forms instead
- **Use `save-excursion`** whenever you move point and don't want to disturb the user
