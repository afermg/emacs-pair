---
name: emacs-pair
description: >-
  Work inside a running Emacs session — read and write buffers, evaluate Elisp,
  run M-x commands, and inspect editor state. Use when the user wants you to
  interact with their live Emacs: read a buffer, modify text, run a command,
  configure something, or debug Elisp in their actual session. Also covers
  working with Emacs packages like elfeed (RSS), mu4e (email), org-mode, and
  any Emacs subsystem accessible through Elisp. Use this whenever the user
  mentions Emacs buffers, elfeed feeds, mu4e mail, org files open in Emacs,
  or wants to evaluate Elisp.
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

## Batch Edits via Elisp Files

For large operations (many line edits, bulk refiling), generate a `.el` file and
evaluate it with `eval-elisp.sh /tmp/my-edits.el`. This avoids shell quoting
issues and the `progn` wrapping heuristic in eval-elisp.sh.

When generating Elisp programmatically (e.g., from Python):
- **Validate paren balance** before writing — count `(` and `)` in the output
- **Process lines in reverse order** when deleting/replacing by line number, so
  earlier indices remain valid
- **Escape strings properly**: backslashes first (`\\` → `\\\\`), then quotes (`"` → `\\"`)
- Wrap everything in a single top-level form (e.g., `with-current-buffer ... save-excursion`)
  rather than multiple top-level expressions — eval-elisp.sh's `progn` wrapper
  can misfire on complex multi-expression files

**Example pattern for bulk line edits:**
```python
lines = ['(with-current-buffer (find-file-noselect "/path/to/file.org")']
lines.append('  (save-excursion')
for line_idx, new_line in sorted(edits, reverse=True):
    esc = new_line.replace('\\', '\\\\').replace('"', '\\"')
    lines.append(f'    (goto-char (point-min))')
    lines.append(f'    (forward-line {line_idx})')
    lines.append(f'    (delete-region (line-beginning-position) (line-end-position))')
    lines.append(f'    (insert "{esc}")')
lines.append('  )')
lines.append('  (save-buffer))')
```

## Working with Elfeed

Elfeed stores its database in memory. Access entries via `elfeed-search-entries`
(in the `*elfeed-search*` buffer) or traverse the full database:

```elisp
;; Iterate all entries for a specific feed URL
(with-elfeed-db-visit (entry feed-obj)
  (when (equal (elfeed-feed-url feed-obj) "https://example.com/feed")
    ;; entry is an elfeed-entry struct
    (elfeed-entry-title entry)
    (elfeed-deref (elfeed-entry-content entry))  ; returns HTML string or nil
    (elfeed-entry-tags entry)))                   ; returns list of symbols
```

Key functions:
- `elfeed-entry-feed` → the feed object for an entry
- `elfeed-feed-title` / `elfeed-feed-url` → feed metadata
- `elfeed-deref` — dereferences content (which is stored lazily)
- `elfeed-db-get-feed` — look up a feed by URL
- Content length from `elfeed-deref` is a good proxy for full-article vs
  headers-only classification (>1500 chars ≈ full article, <300 ≈ headers only)

## Working with mu4e

mu4e runs as a server process inside Emacs that talks to the `mu` binary. The
database lock belongs to this server — don't call `mu index` from the shell
while mu4e is running. Use `(mu4e-update-mail-and-index t)` instead.

### Sending email programmatically

Interactive `message-send-and-exit` prompts for confirmations that hang
emacsclient. Suppress them with `cl-letf`:

```elisp
(let ((buf (generate-new-buffer "*compose*")))
  (with-current-buffer buf
    (mu4e-compose-mode)
    (message-setup '((To . "recipient@example.com")
                     (Subject . "Test")
                     (From . "sender@example.com")))
    (message-goto-body)
    (insert "Body text here.\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (message-send-and-exit))))
```

Alternatively, for simpler sends, bypass message-mode entirely and pipe through
`msmtp` directly:

```elisp
(with-temp-buffer
  (insert "From: sender@example.com\nTo: recipient@example.com\n")
  (insert "Subject: Test\nContent-Type: text/plain; charset=utf-8\n\n")
  (insert "Body here.\n")
  (call-process-region (point-min) (point-max) "msmtp" nil nil nil
                       "--read-envelope-from" "-t"))
```

### Searching contacts

mu4e 1.12+ stores contacts in `mu4e--contacts-set` (a hash table keyed by
email address string):

```elisp
(maphash (lambda (addr props)
           (when (string-match-p "pattern" (downcase addr))
             ...))
         mu4e--contacts-set)
```

### Mode compatibility with modal editors (meow, evil)

mu4e buffers (main, headers, view, compose) use their own single-key bindings
(`q`, `n`, `d`, etc.) that conflict with modal editing normal mode. Add hooks
to switch to insert/emacs state. Note that `mu4e-view-mode` derives from
`gnus-article-mode`, so you need *both* hooks:

```elisp
(dolist (hook '(mu4e-main-mode-hook
                mu4e-headers-mode-hook
                mu4e-view-mode-hook
                mu4e-compose-mode-hook
                gnus-article-mode-hook))
  (add-hook hook #'meow-insert-mode))  ; or #'evil-emacs-state
```

## Working with Org Files via Elisp

When editing org files that Emacs has open, always go through the buffer:

```elisp
(with-current-buffer (find-file-noselect "/path/to/file.org")
  (save-excursion
    ;; Navigate by line number (0-indexed with forward-line)
    (goto-char (point-min))
    (forward-line 41)  ; go to line 42
    ;; Read the line
    (buffer-substring (line-beginning-position) (line-end-position))
    ;; Replace the line
    (delete-region (line-beginning-position) (line-end-position))
    (insert "new content"))
  (save-buffer))
```

For refiling (moving headings between subtrees), collect text in reverse line
order, delete each line, then insert the collected text under the target heading.

## Guard Rails

- **Never write to a file on disk while Emacs has it open** — use `insert`/`save-buffer` instead
- **Avoid `kill-buffer` without asking** — it's destructive and loses unsaved changes
- **Don't run blocking commands** like `read-string` or `yes-or-no-p` interactively —
  they'll hang `emacsclient`. Use non-interactive forms instead. When calling
  functions that might prompt, wrap with `cl-letf` to override `y-or-n-p` and
  `yes-or-no-p`
- **Use `save-excursion`** whenever you move point and don't want to disturb the user
- **Large outputs**: `emacsclient --eval` returns the full Lisp read-syntax of the
  result. For large strings, the output may be truncated or slow. For bulk data
  extraction, write results to a temp file from Elisp and read it back, or
  format output as a structured string you can parse
- **Database locks**: Tools like `mu` and `elfeed` maintain database locks. If Emacs
  owns the lock (server is running), don't call the CLI tool directly for writes —
  use the Emacs API instead (e.g., `mu4e-update-mail-and-index` not `mu index`)
