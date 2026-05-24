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

### TODO fast selection and buffer-local keyword state

Org-mode TODO keyword settings (`org-todo-key-trigger`, `org-todo-key-alist`,
`org-todo-kwd-alist`) are **buffer-local**, set by `org-set-regexps-and-options`
when a buffer enters org-mode. This means:

- If a file has a local `#+TODO:` line, it **overrides** the global
  `org-todo-keywords` for that buffer.
- If that local `#+TODO:` line omits selection keys (e.g.,
  `#+TODO: TODO STARTED | DONE` instead of `#+TODO: TODO(t) STARTED(s) | DONE(d)`),
  then `org-todo-key-trigger` will be nil in that buffer, and `C-c C-t` will
  cycle states instead of showing the fast selection menu — even if
  `org-use-fast-todo-selection` is `t`.
- `org-use-fast-todo-selection` is also buffer-local; setting it globally with
  `setq` won't affect already-open buffers.

**Diagnosis checklist** when `C-c C-t` cycles instead of prompting:

1. Check the buffer-local values:
   ```elisp
   (with-current-buffer "file.org"
     (list :key-trigger (and org-todo-key-trigger t)
           :fast-todo org-use-fast-todo-selection))
   ```
2. If `key-trigger` is nil, look for a local `#+TODO:` line in the file:
   ```elisp
   (with-current-buffer "file.org"
     (save-excursion
       (goto-char (point-min))
       (re-search-forward "^#\\+TODO:" nil t)))
   ```
3. Fix: either remove the local `#+TODO:` line (to inherit global keywords with
   selection keys) or add selection keys to it.

**To fix all open buffers** in the current session after changing keywords:
```elisp
(dolist (buf (buffer-list))
  (with-current-buffer buf
    (when (derived-mode-p 'org-mode)
      (org-set-regexps-and-options))))
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

### Installing mu4e from source via straight.el

mu4e ships with the `mu` binary, not on MELPA. When `mu` is installed via Nix
(or a package manager), mu4e elisp may not be bundled. Install via straight.el
by cloning from GitHub and skipping the build step. The generated
`mu4e-config.el` (normally created by meson) must be produced manually:

```elisp
(use-package mu4e
  :straight (:host github :repo "djcb/mu"
             :branch "release/1.12"
             :files ("mu4e/*.el")
             :pre-build ())
  :init
  ;; Generate mu4e-config.el from the installed mu binary
  (let* ((build-dir (straight--build-dir "mu4e"))
         (config-file (expand-file-name "mu4e-config.el" build-dir)))
    (unless (file-exists-p config-file)
      (let ((mu-ver (string-trim (shell-command-to-string "mu --version | grep -oP '\\d+\\.\\d+\\.\\d+'")))
            (mu-bin (string-trim (shell-command-to-string "which mu"))))
        (with-temp-file config-file
          (insert ";;; mu4e-config.el --- auto-generated -*- lexical-binding: t -*-\n"
                  (format "(defconst mu4e-mu-version \"%s\")\n" mu-ver)
                  (format "(defconst mu4e-doc-dir \"%s\")\n"
                          (expand-file-name "../share/doc/mu" (file-name-directory mu-bin)))
                  "(provide 'mu4e-config)\n"))))))
```

### Multiple accounts with mu4e-contexts

Use `mu4e-contexts` to switch between accounts. Each context sets the
appropriate sent/drafts/trash folders and sender address. mu4e auto-detects
context from the maildir when reading, and prompts when composing:

```elisp
(setq mu4e-contexts
      (list
       (make-mu4e-context
        :name "personal"
        :match-func (lambda (msg)
                      (when msg
                        (string-prefix-p "/personal" (mu4e-message-field msg :maildir))))
        :vars '((user-mail-address  . "me@example.com")
                (mu4e-sent-folder   . "/personal/Sent")
                (mu4e-trash-folder  . "/personal/Trash")))
       (make-mu4e-context
        :name "work"
        :match-func (lambda (msg)
                      (when msg
                        (string-prefix-p "/work" (mu4e-message-field msg :maildir))))
        :vars '((user-mail-address  . "me@work.com")
                ;; Gmail uses special folder names
                (mu4e-sent-folder   . "/work/[Gmail]/Sent Mail")
                (mu4e-trash-folder  . "/work/[Gmail]/Trash")))))
```

For Gmail accounts: IMAP folder names are `[Gmail]/Sent Mail`, `[Gmail]/Drafts`,
`[Gmail]/Trash`. Requires an App Password (https://myaccount.google.com/apppasswords).

### Credential management with rbw (Bitwarden)

mbsync and msmtp both support external password commands. Use `rbw` (unofficial
Bitwarden CLI with background agent) to avoid storing passwords on disk:

- mbsync: `PassCmd "rbw get 'Entry Name'"`
- msmtp: `passwordeval "rbw get 'Entry Name'"`

If `rbw login` fails with pinentry errors over SSH, point it at `pinentry-tty`:
`rbw config set pinentry /path/to/pinentry-tty`

#### Handling rbw vault locking during mu4e sync

When `rbw`'s vault locks (after `lock_timeout` expires or a reboot), `mbsync -a`
fails because `rbw get` can't retrieve passwords. Since `mbsync` runs as a
subprocess of mu4e, there's no TTY for `pinentry-tty` to prompt in.

The solution uses two pieces: a predicate and an interactive unlock command,
wired into mu4e via `:around` advice on both `mu4e` and
`mu4e-update-mail-and-index`.

**Pitfalls learned the hard way:**

- **Don't use `mu4e-update-pre-hook` with `user-error`** — the error fights
  with buffer display and freezes Emacs. Use `:around` advice instead.
- **Don't open mu4e before unlocking** — mu4e's startup triggers a sync, which
  hangs on locked rbw. Unlock first, open mu4e from the sentinel.
- **Don't trust `rbw unlock` exit codes** — verify with `rbw unlocked` in the
  sentinel instead.
- **Don't swap `rbw config set pinentry` at runtime** — changing the config
  kills the rbw agent and loses the unlocked session state.
- **rbw's `lock_timeout` resets on every command** — if mu4e syncs every 5
  minutes, `rbw get` keeps resetting the timer so the vault never locks.
  Track unlock time in Emacs and enforce the timeout yourself.

```elisp
;; Emacs-side session tracking (rbw's own timer resets on every command)
(defvar mu4e--rbw-unlock-time nil)

(defun mu4e--rbw-locked-p ()
  "Return t if rbw is locked or the 8-hour session has expired."
  (when (and mu4e--rbw-unlock-time
             (> (float-time (time-subtract nil mu4e--rbw-unlock-time))
                (* 8 60 60)))
    (call-process "rbw" nil nil nil "lock")
    (setq mu4e--rbw-unlock-time nil))
  (not (zerop (call-process "rbw" nil nil nil "unlocked"))))

;; Interactive unlock — term buffer gives pinentry-tty a real TTY
(defun mu4e-rbw-unlock ()
  "Pop up a terminal to unlock rbw, then open mu4e."
  (interactive)
  (let ((buf (get-buffer-create "*rbw-unlock*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t)) (erase-buffer))
      (term-mode)
      (term-exec buf "rbw-unlock" "rbw" nil '("unlock"))
      (term-char-mode)
      (set-process-sentinel
       (get-buffer-process buf)
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (when-let ((b (process-buffer proc)))
             (when (buffer-live-p b)
               (when-let ((w (get-buffer-window b t)))
                 (delete-window w))
               (kill-buffer b)))
           (if (zerop (call-process "rbw" nil nil nil "unlocked"))
               (progn
                 (setq mu4e--rbw-unlock-time (current-time))
                 (mu4e))
             (message "rbw unlock failed"))))))
    (display-buffer buf '((display-buffer-at-bottom) (window-height . 3)))
    (select-window (get-buffer-window buf t))
    (when (bound-and-true-p meow-mode) (meow-insert-mode))))

;; Background syncs silently skip when locked
(advice-add 'mu4e-update-mail-and-index :around
  (lambda (orig-fn &rest args)
    (if (mu4e--rbw-locked-p)
        (message "rbw is locked — M-x mu4e-rbw-unlock to resume")
      (unless mu4e--rbw-unlock-time
        (setq mu4e--rbw-unlock-time (current-time)))
      (apply orig-fn args))))

;; Opening mu4e when locked → unlock first
(advice-add 'mu4e :around
  (lambda (orig-fn &rest args)
    (if (mu4e--rbw-locked-p)
        (mu4e-rbw-unlock)
      (apply orig-fn args))))
```

### Sending email programmatically

Use `mu4e-compose-mail` to create compose buffers — it properly sets up Fcc
headers, hooks, and mu4e integration. Using `message-setup` directly skips
mu4e's machinery (no Fcc, no sent-folder save, no context switching).

Interactive prompts (`y-or-n-p`, "Fix continuation lines?") hang emacsclient.
Suppress them with `cl-letf`:

```elisp
;; Preferred: uses mu4e-compose-mail for full mu4e integration (Fcc, sent folder)
(progn
  (mu4e-compose-mail "recipient@example.com" "Subject line")
  (let ((buf (car (seq-filter (lambda (b)
                                (with-current-buffer b
                                  (derived-mode-p 'mu4e-compose-mode)))
                              (buffer-list)))))
    (with-current-buffer buf
      (message-goto-body)
      (insert "Body text here.\n")
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (message-send-and-exit)))))
```

For fire-and-forget sends where you don't need sent-folder integration,
bypass message-mode entirely and pipe through `msmtp`:

```elisp
(with-temp-buffer
  (insert "From: sender@example.com\nTo: recipient@example.com\n")
  (insert "Subject: Test\nContent-Type: text/plain; charset=utf-8\n\n")
  (insert "Body here.\n")
  (call-process-region (point-min) (point-max) "msmtp" nil nil nil
                       "--read-envelope-from" "-t"))
```

This won't save to Sent — use it only for quick one-off sends where that's OK.

### Replying to a specific message (wide-reply) by message-id

To compose a reply-all to an existing message from headless `emacsclient` — for
picking up an in-flight email thread programmatically. Two non-obvious gotchas:

1. `mu4e-headers-search` is asynchronous. After calling it you must wait for
   results to populate; otherwise `mu4e-compose-wide-reply` raises
   `[mu4e] No message at point`.
2. `(goto-char (point-min))` is not enough — the headers buffer has marker
   bytes before the first message line. Call `mu4e-headers-next` to land on a
   valid message row.

Body injection via an `emacsclient -e` string would require painful elisp
escaping. Use a temp-file sentinel: write the body to disk, register a
one-shot `mu4e-compose-mode-hook` that reads it and inserts at body position,
then trigger the reply. The hook fires when the compose buffer is created.

```elisp
(progn
  ;; one-shot body inserter (reads from /tmp/wide-reply-body.txt)
  (let ((inserter nil))
    (setq inserter
          (lambda ()
            (when (file-exists-p "/tmp/wide-reply-body.txt")
              (save-excursion
                (message-goto-body)
                (insert-file-contents "/tmp/wide-reply-body.txt"))
              (remove-hook 'mu4e-compose-mode-hook inserter))))
    (add-hook 'mu4e-compose-mode-hook inserter))
  (mu4e-headers-search "msgid:MESSAGE-ID-NO-ANGLES")
  (sleep-for 2)  ; wait for async search results
  (when (get-buffer mu4e-headers-buffer-name)
    (with-current-buffer mu4e-headers-buffer-name
      (goto-char (point-min))
      (mu4e-headers-next)               ; land on a real message line
      ;; (mu4e-headers-next)            ; optional: skip to Nth result
      (mu4e-compose-wide-reply))))
```

Get the msgid via `mu find … --fields i` or `mu view <path>`. The query form
`msgid:abc@example.com` (without angle brackets) is what mu accepts.

After the compose buffer exists, raise it to the user's frame:

```elisp
(let ((buf (car (cl-remove-if-not
                 (lambda (b) (with-current-buffer b
                               (derived-mode-p 'message-mode)))
                 (buffer-list)))))
  (when buf
    (select-window (display-buffer buf))
    (with-current-buffer buf (message-goto-body))
    (select-frame-set-input-focus (window-frame (selected-window)))))
```

For follow-up edits to the same buffer (e.g. inserting an extra paragraph
before the user sends), find a stable sentinel string and `search-forward` +
`insert`:

```elisp
(with-current-buffer "COMPOSE-BUFFER-NAME"
  (save-excursion
    (goto-char (point-min))
    (when (search-forward "Could you add" nil t)
      (beginning-of-line)
      (insert "EXTRA PARAGRAPH HERE.\n\n"))))
```

The sentinel needs to be unique enough not to collide with the citation
block, signature, or any edits the user may have already made.

### Diagnosing "send hangs forever"

When mu4e send (or any msmtp call) hangs indefinitely, **verify the SMTP
socket before chasing rbw, pinentry, emacs advice, or compose-buffer quirks**.
Password retrieval is fast (a few ms via `rbw-agent` over a Unix socket), so a
long hang almost always means msmtp is blocked on the network, not the
credential path.

**Fast check — `/dev/tcp` probe for the SMTP banner:**

```bash
# Expect: a "220 <host> ESMTP ..." line within a second or two
timeout 10 bash -c 'exec 3<>/dev/tcp/<host>/<port>; head -1 <&3'
```

Possible outcomes:
- **Banner arrives** → server is healthy; the hang is elsewhere (TLS, auth, emacs advice).
- **TCP connects but no banner, then timeout** → a firewall or transparent
  proxy is silently dropping the server → client data. msmtp is blocked on
  `recvfrom` and will never recover. Switch to a different submission port
  (try 465 / implicit TLS if you were on 587 / STARTTLS, or vice versa).
- **TCP refused / no route** → routing or firewall at layer 3. Different
  problem; `traceroute`, check VPN/network.

**Telltale sign it's the network, not the server:** if *two independent
providers* (e.g. mxroute and Gmail) both hang on the same port at the same
time, it's the local network. Providers don't coordinate outages — identical
symptoms = client-side.

**strace confirms it unambiguously** if `/dev/tcp` is ambiguous:

```bash
timeout 10 strace -f -e trace=network -o /tmp/msmtp.trace \
  sh -c 'printf "From: x\nTo: x\nSubject: x\n\n" | msmtp --read-envelope-from -t'
tail -30 /tmp/msmtp.trace
```

Look for the pattern:
```
connect(..., sin_port=htons(587)) = 0              # TCP handshake succeeded
recvfrom(..., 4096, 0, NULL, NULL) = ? ERESTARTSYS # blocked reading banner
```
That's a network blackhole on port 587. `rbw get …` succeeding earlier in the
same trace rules out the credential path.

**Switching to implicit TLS (port 465)** in `msmtprc`:
```
port 465
tls_starttls off
```
(Leave `tls on` — implicit TLS still encrypts from the first byte; only the
STARTTLS upgrade is turned off.)

This failure mode tricks you into debugging rbw/pinentry/emacs because the
password fetch happens *before* the SMTP hang, so "recent changes to the auth
layer" become the first suspect. Always probe the socket first.

### Deleting / moving email programmatically

`mu4e--server-move` requires a message docid (not a file path), which makes it
awkward from non-interactive Elisp. The reliable approach is to move the maildir
files directly, then sync:

```elisp
;; Move messages to Trash by renaming files in the maildir
(let ((files '("/path/to/.mail/account/Inbox/cur/msg-file:2,S"))
      (trash-dir "/path/to/.mail/account/Trash/cur/"))
  (dolist (path files)
    (when (file-exists-p path)
      (let* ((basename (file-name-nondirectory path))
             ;; Add T (trashed) flag to maildir flags
             (new-name (if (string-match ":2,\\(.*\\)" basename)
                           (let ((flags (match-string 1 basename)))
                             (unless (string-match-p "T" flags)
                               (replace-match (concat ":2," flags "T") nil nil basename)))
                         basename)))
        (rename-file path (concat trash-dir (or new-name basename)))))))
;; Then sync so deletions propagate to the IMAP server
(mu4e-update-mail-and-index t)
```

mbsync syncs bidirectionally — moving files to Trash locally propagates to the
server, so changes will appear in webmail too.

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

Buffers like mu4e, magit, and other special-mode packages use their own
single-key bindings (`q`, `n`, `d`, etc.) that conflict with modal editing
normal mode. The reliable way to force insert state is `meow-mode-state-list`
— hooks can be overridden by `meow-global-mode` re-entering normal state
after the hook runs.

```elisp
;; Preferred: meow-mode-state-list — meow checks this before choosing state
(with-eval-after-load 'meow
  (dolist (entry '((mu4e-main-mode . insert)
                   (mu4e-headers-mode . insert)
                   (mu4e-view-mode . insert)
                   (mu4e-compose-mode . insert)
                   (gnus-article-mode . insert)   ; mu4e view uses gnus-article-mode
                   (magit-status-mode . insert)
                   (magit-log-mode . insert)
                   (magit-diff-mode . insert)))
    (add-to-list 'meow-mode-state-list entry)))
```

For evil-mode, use `evil-set-initial-state` instead:

```elisp
(evil-set-initial-state 'mu4e-main-mode 'emacs)
(evil-set-initial-state 'magit-status-mode 'emacs)
;; etc.
```

**Do not use hooks** like `(add-hook 'mu4e-view-mode-hook #'meow-insert-mode)`
— `meow-global-mode` can override the state after the hook fires, making
insert mode appear to not work.

#### When state-list isn't enough: fully disable meow in a mode

`meow-mode-state-list` only selects *which* state meow enters — it can't
turn meow off. For modes where every state gets in the way (e.g. dired
with `dired-subtree`'s TAB/S-TAB cycling, or heavy-TUI terminal modes
where you want raw keyboard passthrough), advise the globalized turn-on
function instead:

```elisp
(with-eval-after-load 'meow
  (define-advice meow-global-mode-enable-in-buffer
      (:around (orig-fn &rest args) afm/skip-dired)
    (unless (derived-mode-p 'dired-mode)
      (apply orig-fn args))))
```

Why advice and not a `dired-mode-hook` with `(meow-mode -1)`? `run-mode-hooks`
fires the mode's own hook *before* `after-change-major-mode-hook`, and
`meow-global-mode`'s enable-in-buffer runs from the latter — so the hook's
disable gets silently undone a moment later. The advice is the only reliable
interception point.

After installing this kind of advice live, remember to toggle meow off in
any already-open buffers of that mode — the advice only controls new
buffers:

```elisp
(dolist (buf (buffer-list))
  (with-current-buffer buf
    (when (derived-mode-p 'dired-mode)
      (meow-mode -1))))
```

## Working with Magit

### Reinstating `m Magit` in `project-switch-project`

Modern magit's wiring for `C-x p m` / the "Magit" entry in
`project-switch-commands` lives in `magit-extras.el`, not magit's autoloads:

```elisp
;; In magit-extras.el — NO ;;;###autoload cookie above this form:
(with-eval-after-load 'project
  (when (and magit-bind-magit-project-status
             (equal project-switch-commands
                    (eval (car (get 'project-switch-commands 'standard-value)) t)))
    (keymap-set project-prefix-map "m" #'magit-project-status)
    (add-to-list 'project-switch-commands '(magit-project-status "Magit") t)))
```

Two traps stack here:

1. **Not autoloaded** — the form only runs if something explicitly
   `(require 'magit-extras)`. A bare `(use-package magit)` doesn't pull it
   in, so the binding never registers.
2. **Equality guard** — even if `magit-extras` loads, magit only injects
   when `project-switch-commands` still equals its standard-value. Any prior
   modification of the list (by another package, your own config, or even
   an earlier evaluation during the same session) silently disables the
   injection.

**Diagnosis**:

```elisp
(list :prefix-m (lookup-key project-prefix-map "m")
      :switch-cmds project-switch-commands
      :magit-project-status (when (fboundp 'magit-project-status)
                              (let ((fn (symbol-function 'magit-project-status)))
                                (if (autoloadp fn) 'autoload 'loaded))))
```

If `:prefix-m` is nil but `:magit-project-status` is `autoload`, the
autoload stub is registered but the wiring form never ran — symptom
matches both failures above.

**Fix** — wire it yourself from your own config, independent of magit-extras:

```elisp
(with-eval-after-load 'project
  (keymap-set project-prefix-map "m" #'magit-project-status)
  (add-to-list 'project-switch-commands '(magit-project-status "Magit") t))
```

`magit-project-status` is autoloaded, so calling it triggers magit load
lazily. `add-to-list` is idempotent, so re-evaluating this form is safe.
This is robust to both the missing autoload and the equality guard.

## Working with mini-echo (echo-area modeline)

[mini-echo](https://github.com/eki3z/mini-echo.el) renders the modeline in
the echo area instead of per-window. Customising it has several traps
worth knowing before you start editing `:config` blocks.

### Rule order is reversed at render time

`mini-echo-concat-segments` fetches each rule entry, filters empties, then
calls `(reverse ...)` before joining. So **the first segment in the rule
appears rightmost on screen**, not leftmost. A rule of
`("time" "hostname" "buffer-name")` renders as `buffer-name hostname time`.
Write the rule in reverse visual order; leave a comment stating this so
the next reader doesn't flip it "to match".

### `:both` collapses `:long`/`:short` duplication

`mini-echo-normalize-rule` reads `:both` specially: if the rule plist
contains `:both`, its value is used for both the long and short buckets.
Use it whenever the two lists would be identical:
```elisp
(setq mini-echo-persistent-rule
      '(:both ("flymake" "project" "hostname" "buffer-name"
               "vcs" "buffer-position" "meow")))
```

### `mini-echo-persistent-detect` overrides the user rule

For certain majors — magit-*-mode, `dired-mode`, `ibuffer-mode`,
`diff-mode`, `helpful-mode`, `xwidget-webkit-mode`,
`profiler-report-mode`, `rg-mode`, `org-src`, `atomic-chrome-edit-mode`,
`magit-blob-mode`, popper-controlled buffers, `treesit--explorer-tree-mode`
— `mini-echo-persistent-detect` returns a hard-coded `(:both (...))` rule
that **completely bypasses** `mini-echo-persistent-rule`. If you want a
segment visible everywhere (hostname, vcs, a state indicator), you have
to inject it into that function's return:

```elisp
;; Keep hostname + vcs visible even in the hard-coded detections.
(define-advice mini-echo-persistent-detect
    (:filter-return (rule) afm/always-hostname+vcs)
  (when rule
    (let ((extra '("hostname" "vcs")))
      (cl-loop for (key val) on rule by #'cddr
               append (list key
                            (append (seq-difference extra val) val))))))
```

Prepend vs append to `val` determines whether the extras end up on the
right side of the rendered line (prepend — they become rightmost after
the reverse) or the left (append).

### Refresh caches after changing the rule at runtime

`(setq mini-echo-persistent-rule …)` isn't enough — the merged rule is
cached in `mini-echo--default-rule` (rebuilt by `mini-echo-ensure`) and
memoised per-buffer in `mini-echo--selected-rule`. After editing the
rule live, do all three:

```elisp
(dolist (buf (buffer-list))
  (with-current-buffer buf
    (kill-local-variable 'mini-echo--selected-rule)))
(setq-default mini-echo--selected-rule nil)
(mini-echo-ensure)
(mini-echo-update-overlays)
```

Same treatment is needed when you define a new segment or flip the rule
order — the new segments won't show up in any open buffer otherwise.

### Segments that silently depend on another mode

Two stock segments get you in trouble because their `:fetch` depends on
state that another package toggles:

- `remote-host` — only fires inside TRAMP buffers (tests
  `(file-remote-p default-directory 'host)`), so on a local machine it
  prints nothing. For "always show the local hostname," define your own:
  ```elisp
  (mini-echo-define-segment "hostname"
    "Short hostname of the local machine."
    :fetch (mini-echo-segment--print
            (car (split-string (system-name) "\\."))
            'mini-echo-remote-host))
  ```
- `time` — its `:setup` calls `(display-time-mode 1)` once, then the
  `:fetch` reads `display-time-string`. If anything (stale config, old
  hand-rolled modeline, toggling) disables `display-time-mode` again,
  the segment goes blank and the `:setup` never re-runs (the segment's
  `activate` slot is sticky). Use a self-contained version instead:
  ```elisp
  (mini-echo-define-segment "time"
    "HH:MM — re-evaluated every `mini-echo-update-interval' (0.3s)."
    :fetch (format-time-string "%H:%M"))
  ```

### Re-running a segment's `:setup`

`mini-echo-define-segment` stores an `activate` flag on the segment
struct; `:setup` runs exactly once per session. To force it again after
changing something (e.g. flipping `display-time-mode` after the first
activation):
```elisp
(when-let* ((seg (alist-get "time" mini-echo-segment-alist
                            nil nil #'string=)))
  (setf (slot-value seg 'activate) nil))
```

### Distinct colors per segment

Two mechanisms, pick based on whether you own the segment:
- **You redefined the segment**: pass the face as the second arg to
  `mini-echo-segment--print`:
  ```elisp
  (mini-echo-define-segment "vcs"
    :fetch (when (bound-and-true-p vc-mode)
             (mini-echo-segment--print
              (mini-echo-segment--extract vc-mode)
              'font-lock-keyword-face
              mini-echo-vcs-max-length)))
  ```
  (The stock `vcs` uses dynamic `vc-*-state` faces, which blend into the
  rest of the modeline — pinning to a named face is the fix.)
- **Stock segment, customise via its face**: remap `mini-echo-<name>` to
  inherit from a theme face so it follows the palette:
  ```elisp
  (dolist (spec '((mini-echo-buffer-position . font-lock-variable-name-face)
                  (mini-echo-major-mode      . font-lock-type-face)
                  (mini-echo-buffer-size     . shadow)))
    (set-face-attribute (car spec) nil
                        :foreground 'unspecified
                        :background 'unspecified
                        :inherit (cdr spec))))
  ```

### Right-alignment and padding

mini-echo right-aligns via `(space :align-to (- right-fringe padding))`
where `padding = mini-echo-right-padding + content-length`.

- Leave `mini-echo-right-padding` at ≥ 2. `0` clips the last character
  on some frames (TTY + fringes in particular).
- When content is wider than the minibuffer, the LEFT of the string is
  clipped — so the leftmost segment in the reversed render disappears
  first. Put the most-important segment last in the rule (rightmost on
  screen) if you care about it being visible when overflowing.

### Single-line echo area

```elisp
(setq resize-mini-windows 'grow-only     ; grow but don't freeze
      max-mini-window-height 1)
```

Traps:

- `resize-mini-windows nil` **freezes** the minibuffer at whatever
  height it was when you set it. If it was already 2 lines from an
  overflow, you're stuck there. Always `grow-only` (or `t`) and shrink
  explicitly:
  ```elisp
  (let ((mw (minibuffer-window)))
    (when (> (window-total-height mw) 1)
      (window-resize mw (- 1 (window-total-height mw)) nil nil 'preserve)))
  ```
- Mini-echo's mode hiding (`mini-echo-hide-mode-line`) enables
  `global-hide-mode-line-mode` and, on Emacs < 31, runs a 5-second
  timer to force-apply `hide-mode-line-mode` to buffers that missed the
  globalised hook. A brief flash of the native modeline at startup is
  expected.

### Background tint without losing text contrast

The minibuffer's rendering face is `mini-echo-minibuffer-window`,
applied via `(face-remap-add-relative 'default 'mini-echo-minibuffer-window)`.
Setting `:inherit mode-line-inactive` on it tints the background
nicely but **also** imports that face's dim grey foreground — mini-echo
text then loses contrast against the echo area.

You can't inherit only `:background` from one face: `:inherit` is
all-or-nothing per unset attribute. Resolve the two sources explicitly,
and rehook on theme change:
```elisp
(defun afm/mini-echo-refresh-minibuf-face ()
  (set-face-attribute 'mini-echo-minibuffer-window nil
                      :foreground (face-attribute 'default :foreground)
                      :background (face-attribute 'mode-line-inactive :background)
                      :inherit 'unspecified))
(afm/mini-echo-refresh-minibuf-face)
(add-hook 'enable-theme-functions
          (lambda (_) (afm/mini-echo-refresh-minibuf-face)))
```

### Meow state as a single-char segment

`meow--current-state` is the state symbol (`normal`, `insert`, `motion`,
`keypad`, `beacon`). Map each to a letter with its own face so state is
readable at a glance:

```elisp
(mini-echo-define-segment "meow"
  "Single-character meow state indicator."
  :fetch
  (when (bound-and-true-p meow-mode)
    (pcase (and (boundp 'meow--current-state) meow--current-state)
      ('normal (mini-echo-segment--print "N" 'font-lock-builtin-face))
      ('insert (mini-echo-segment--print "I" 'success))
      ('motion (mini-echo-segment--print "M" 'font-lock-comment-face))
      ('keypad (mini-echo-segment--print "K" 'error))
      ('beacon (mini-echo-segment--print "B" 'mode-line-emphasis))
      (_       (mini-echo-segment--print "?" 'shadow)))))
```

### Conditionally-visible segments

A `:fetch` that returns `nil` is filtered out by
`mini-echo-concat-segments` — no need for a predicate around the rule
entry. Two useful examples:

- Flymake only in prog-mode buffers: leave stock `"flymake"` in the rule;
  `(when (bound-and-true-p flymake-mode) …)` in its fetch handles it.
- Clock only in fullscreen frames:
  ```elisp
  (mini-echo-define-segment "time"
    :fetch (when (memq (frame-parameter nil 'fullscreen)
                       '(fullboth fullscreen maximized))
             (format-time-string "%H:%M")))
  ```

## Trial-installing third-party packages

Before promoting a package into the user's tracked config (Nix + straight.el),
load it ephemerally so they can try it without committing to a rebuild. The
pattern: clone, `add-to-list 'load-path`, `require`, configure, use. When
done, undo every side-effect so the daemon is back to its starting state.

### Install

```bash
git clone --depth 1 https://github.com/owner/pkg /tmp/pkg-trial
```

```elisp
(progn
  (add-to-list 'load-path "/tmp/pkg-trial")
  (require 'pkg))
```

Then activate any modes the user wants to test, configure variables, etc.

### Tear down without restarting the daemon

```elisp
(progn
  ;; 1. Disable any modes the package activated
  (when (bound-and-true-p some-mode) (some-mode -1))
  ;; 2. Cancel package timers (otherwise they keep firing on dead state)
  (when (boundp 'pkg--timer)
    (when pkg--timer (cancel-timer pkg--timer))
    (setq pkg--timer nil))
  ;; 3. Drop the trial load-path entry
  (setq load-path
        (cl-remove-if (lambda (p) (string-match-p "/tmp/pkg-trial" p))
                      load-path))
  ;; 4. Unload the feature (FORCE arg also reverses hook installations)
  (ignore-errors (unload-feature 'pkg t))
  ;; 5. Reset env vars you spoofed for protocol/feature detection
  (setenv "FOO" nil)
  ;; 6. Kill test buffers
  (dolist (b '("test-input.png" "*pkg-debug*"))
    (when (get-buffer b)
      (let ((kill-buffer-query-functions nil)) (kill-buffer b)))))
```

`unload-feature` with FORCE removes most defs and reverses hooks the package
added — but it can't undo `defvar` side effects in *other* packages or `setq`
modifications. After unload, verify with `(featurep 'pkg)` returns nil.

### Daemon `process-environment` ≠ frame env

When the user's Emacs runs as a daemon (systemd unit, login service, GUI
launcher), `process-environment` is fixed at daemon startup. Frames that
attach later via `emacsclient -nw` — especially over SSH — don't propagate
their env vars into the daemon. So `(getenv "KITTY_PID")`,
`(getenv "TERM_PROGRAM")`, `(getenv "TERM")` etc. reflect the daemon's launch
context (typically nil/`dumb`), not the actual terminal showing the frame.

Packages that auto-detect features from env vars (terminal-graphics
protocols, color schemes, anything sniffing `TERM_PROGRAM`) will mis-detect.
Two paths:

- **Spoof before detection**: `(setenv "KITTY_PID" "ssh-trial")` then trigger
  the package's detect function.
- **Skip detection**: most packages expose an override (e.g.
  `kitty-gfx-preferred-protocol`, `theme-detect-bg-fn`). Setting that to a
  concrete value bypasses env sniffing entirely.

### Terminal-graphics packages: pitfalls

Packages emitting graphics escape sequences (kitty-graphics.el, eat,
xterm-mouse-mode-extras, anything using `send-string-to-terminal` for
APC/DCS/OSC payloads) need extra care.

#### `send-string-to-terminal` follows the *selected* frame's tty

When the daemon serves multiple tty frames from different terminals (kitty +
WezTerm + ghostty all attached), the next render hook emits to whichever
frame is currently selected. Pin focus before triggering output:

```elisp
(let ((target (cl-find-if (lambda (f) (equal (frame-parameter f 'name) "F10"))
                          (frame-list))))
  (select-frame-set-input-focus target)
  ;; ...trigger render here...)
```

And warn the user: switching focus to a non-supporting terminal while the
mode is active can trigger a redisplay that emits the protocol there too.

#### Blocking `read-event` queries can freeze the terminal

Many packages query terminal state interactively — XTWINOPS (`CSI 16 t` for
cell pixel size), DA1 (`CSI c` for capabilities), OSC 4 color queries, etc.
The pattern is `send-string-to-terminal` followed by `read-event` in a loop.
If the terminal doesn't reply in the expected shape (or replies slowly), the
loop blocks emacsclient for the timeout duration. Worse, if the package has
already emitted other escape sequences (e.g. kitty-graphics APC payloads),
the terminal is left mid-parse — appearing fully frozen until the user
closes the tab.

Mitigations:

- **Pre-cache the answer** so the query never runs:
  ```elisp
  (setq kitty-gfx--cell-pixel-width  10
        kitty-gfx--cell-pixel-height 20)
  ```
- **If a freeze happens**, immediately disable the offending mode globally
  via `eval-elisp.sh` from outside the frozen frame — that stops *further*
  bytes but doesn't unfreeze the terminal mid-parse. The user has to close
  the tab or kill the emacsclient process to recover.

#### Backend swap: clear the agnostic cache

Packages with multiple rendering backends (kitty-graphics has kitty + sixel)
often keep a backend-agnostic file→id cache plus per-backend sub-caches.
Switching the active backend at runtime doesn't invalidate the agnostic
cache, so the backend-specific `prepare` step is skipped on the next render
and the new backend's sub-cache stays empty. Symptom in kitty-graphics: log
shows `sixel-place: no PNG cached for /path/to/file`. Fix:

```elisp
(clrhash kitty-gfx--image-cache)
(setq kitty-gfx--cache-lru nil)
(clrhash kitty-gfx--sixel-cache)
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

## Managing Application Configs via NixOS / Home Manager

This user manages their system declaratively with NixOS and Home Manager. When
adding or modifying application configuration, prefer creating a declarative
`.nix` module rather than editing dotfiles directly.

### Two mechanisms for dotfile management

1. **`xdg.configFile`** — for apps that use `~/.config/<app>/`. Create a
   standalone `.nix` module, then import it in `homes/amunoz/home.nix`:

   ```nix
   # modules/shared/config/email/rbw.nix
   { pkgs, ... }:
   {
     xdg.configFile."rbw/config.json" = {
       text = builtins.toJSON {
         lock_timeout = 28800;
         pinentry = "${pkgs.pinentry-curses}/bin/pinentry-tty";
       };
     };
   }
   ```

2. **`home.file`** — for apps that use `~/.<file>` (non-XDG). Defined in
   `modules/shared/files.nix`:

   ```nix
   ".mbsyncrc" = {
     text = builtins.readFile ../shared/config/email/mbsyncrc;
   };
   ```

3. **`mkOutOfStoreSymlink`** — for files the user edits frequently. Instead of
   copying the content into the read-only Nix store (which forces a
   `home-manager switch` after every edit), link the managed path back to the
   repo working tree. Edits to the repo become live immediately:

   ```nix
   ".emacs.d/init.el" = {
     source = config.lib.file.mkOutOfStoreSymlink
       "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/emacs/init.el";
   };
   ```

   Use this for editor configs, shell rc files, and anything else the user
   iterates on. Reserve `builtins.readFile` for files that are effectively
   frozen (lock templates, canned credentials). Tradeoff the user accepts:
   the live config tracks the working tree, not the committed state.

### Key patterns

- **Reference Nix packages for paths** — use `"${pkgs.pinentry-curses}/bin/pinentry-tty"`
  instead of hardcoded `/nix/store/...` paths. Hardcoded store paths break on
  package updates.
- **Use `builtins.toJSON`** for JSON configs — lets you write Nix attribute sets
  that get serialized correctly.
- **Use `builtins.readFile`** for configs that aren't easily expressed in Nix
  (e.g., mbsyncrc, msmtprc).
- **Standalone modules** — each app config gets its own `.nix` file under
  `modules/shared/config/<category>/`, imported in `homes/amunoz/home.nix`:

  ```nix
  imports = [
    ../../modules/shared/config/opencode/opencode.nix
    ../../modules/shared/config/email/rbw.nix
  ];
  ```

- **`onChange`** — use for post-deploy fixups, but note that `home.file`
  entries land as symlinks into the read-only `/nix/store`, so `chmod` on
  the target will fail with `Read-only file system`. Permission-sensitive
  configs (like msmtp's strict 0600 requirement) should not be managed
  via `home.file` — use the dedicated home-manager module instead (see
  next section).

### Installing Emacs packages

When the user's Emacs config is driven by a literate `config.org` that uses
`use-package` + `straight.el`, install new Emacs packages inside `config.org`,
**not** via the `emacs.pkgs.withPackages` list in `home.nix`.

```org
*** Startup profiler (esup)
#+begin_src emacs-lisp
  (use-package esup
    :straight t
    :commands (esup))
#+end_src
```

Why prefer this over the Nix path:

- The Emacs init (init.el / config.org) is typically symlinked via
  `mkOutOfStoreSymlink`, so adding a package there takes effect on the next
  Emacs eval — no `home-manager switch` required.
- Routing packages through Nix forces a rebuild for each tweak and obscures
  the relationship between the package and the config that configures it.
- `straight.el` pins revisions in `straight/versions/default.el`, giving you
  reproducibility without the Nix round-trip.

Reserve the Nix `withPackages` list for the rare case where an Emacs package
has a native dependency that `straight.el` cannot build (e.g., tree-sitter
grammars shipped by a Nix overlay, or packages that wrap a non-Emacs binary
that needs to be in `PATH`).

### Adding external flake inputs with overlays

When a package comes from an external flake (not nixpkgs), add it as a flake
input and expose it via an overlay so it's available as `pkgs.<name>` everywhere.

**Step 1 — Add the flake input** in `flake.nix` under `inputs`:

```nix
my-tool.url = "github:owner/repo";
```

**Step 2 — Add an overlay** in `overlays/default.nix`:

```nix
my-tool =
  final: _: {
    my-tool = inputs.my-tool.packages.${final.stdenv.hostPlatform.system}.default;
  };
```

This makes `pkgs.my-tool` available in NixOS modules, Home Manager, and
anywhere else that receives `pkgs`. If the flake exposes its own overlay
(like emacs-overlay does), prefer using that directly:

```nix
my-tool = inputs.my-tool.overlay;
```

After adding the overlay, the package can be used in `home.packages`,
`environment.systemPackages`, or any other package list.

### `accounts.email.passwordCommand`: no shell escaping

The home-manager msmtp module (and likely other `accounts.email`
consumers) renders `passwordCommand` via plain `toString`, with **no
shell escaping**. A list like `[ "rbw" "get" "Broad Email App Password" ]`
becomes the literal line

```
passwordeval rbw get Broad Email App Password
```

so `/bin/sh -c` then passes four separate args to `rbw` and the lookup
fails silently (msmtp surfaces an opaque auth error). Passing the
command as a single string also fails: the option's `apply` does
`splitString " "` first, which destroys the outer quotes.

**The fix is to embed shell quotes inside the list element itself:**

```nix
accounts.email.accounts.broad = {
  passwordCommand = [ "rbw" "get" "'Broad Email App Password'" ];
  # …
};
```

That renders as `passwordeval rbw get 'Broad Email App Password'`, which
the shell parses correctly so `rbw` receives one argument.

Verify the rendered output before activating:

```sh
nix derivation show $(nixos-rebuild build --flake .#<host> --print-out-paths) \
  | jq -r '..|.text? // empty' | grep passwordeval
```

The build will succeed regardless — the breakage is only visible at
runtime when msmtp tries to fetch credentials.

### msmtp specifically: don't manage `~/.msmtprc` via `home.file`

msmtp refuses to use any rc file that isn't mode 0600. With
`home.file.".msmtprc"`, the file lands as a symlink into
`/nix/store/...-home-manager-files/.msmtprc`, and any `onChange = "chmod
600 $HOME/.msmtprc"` fails because the target lives on a read-only
filesystem. The home-manager activation reports

```
chmod: changing permissions of '/home/<user>/.msmtprc': Read-only file system
home-manager-<user>.service: Failed with result 'exit-code'.
```

Use `programs.msmtp.enable = true;` plus `accounts.email.accounts.<n>`
instead — that writes a proper mode-0600 file at
`~/.config/msmtp/config`, which msmtp's default search order picks up
without any explicit `-C` flag (so emacs `(setq sendmail-program
"msmtp")` keeps working).

### Emacs settings that need Nix-aware workarounds

Some Emacs interactions assume a writable `custom-file`. Under Nix, that
file is either missing, read-only, or regenerated on rebuild, so anything
that relies on persistence via `custom-set-variables` silently fails to
stick — Emacs re-prompts on every launch.

**Theme-trust prompt** is the most common case. `load-theme` asks
"Loading a theme can run Lisp code — really load?" and, on confirmation,
writes the theme's SHA to `custom-file` via `customize-push-and-save`.
Under Nix that write either errors out or gets blown away on the next
home-manager switch, so the prompt returns every session.

Bypass the prompt explicitly rather than trying to persist the answer:

```elisp
(use-package modus-themes
  :config
  ;; Nix stores the config read-only, so `custom-file' can't persist the
  ;; "trust this theme" answer. Trust up front instead of prompting.
  (setq custom-safe-themes t)
  (load-theme 'modus-vivendi-tritanopia :no-confirm))
```

Same pattern applies to any other setting that normally lives in
`custom-file` (package-archive-priorities, TRAMP connection history, etc.)
— surface them into your tracked init code with plain `setq`, or accept
that they won't persist across rebuilds. The general rule: if Nix owns
the dotfile, don't rely on Customize for anything.

## Working with `eat` (terminal-emulator buffers)

`eat` runs a child process inside an Emacs-allocated PTY. The buffer
shows that process's terminal output rendered through eat's own
TUI engine. Several non-obvious gotchas come up when scripting eat
from Elisp.

### Test from inside the actual daemon, not via `eval-elisp.sh`

`bash scripts/eval-elisp.sh` runs the shell with stdin redirected
from `/dev/null`. Any program that requires its caller to have a
controlling terminal — `screen -x`, `screen -r`, `dtach -a` — will
fail with errors like `"Must be connected to a terminal."`.

The actual Emacs daemon's eat allocates a real PTY for its
subprocesses (it uses `:connection-type 'pty` under `make-process`),
so the same code paths *do* work in real interactive use. When you
need to validate a multiplexer / PTY-attach path, do it via
`emacsclient`-driven elisp inside the live daemon — don't trust
`eval-elisp.sh` results for this category.

### `eat-mode` resets buffer-local variables on init

Several eat customizations like `eat-term-name` and
`eat-enable-shell-prompt-annotation` are defcustoms that
`eat-mode`'s body resets to their default values during major-mode
initialization. So this **doesn't work**:

```elisp
(setq-local eat-term-name "xterm-256color")  ; clobbered by eat-mode
(eat-mode)
(eat-exec ...)
```

Set them **after** `eat-mode` but **before** `eat-exec`:

```elisp
(eat-mode)
(setq-local eat-term-name "xterm-256color")
(eat-exec ...)
```

Conversely `eat-enable-shell-prompt-annotation` *can* be set before
`eat-mode` because the annotation is installed by mode-hooks, not by
the mode body itself.

### Override `eat-term-name` when wrapping in `screen`

GNU `screen` rejects eat's default `TERM=eat-256color` with
`"Clear screen capability required"` — eat-256color's `clear` cap is
`\E[2J` (no cursor home), screen wants `\E[H\E[2J`. Override to
`xterm-256color` (any standard TERM with a screen-compatible clear
cap) for screen-wrapped subprocesses. `dtach` has no such issue —
it's a transparent PTY relay with no terminfo opinions of its own.

### Eat kills its buffer on process exit by default

`eat-kill-buffer-on-exit` defaults to `t`. If you spawn a process
that exits immediately (e.g. `screen -x` failing because TERM is
wrong, or `dtach -a` against a missing socket), eat will kill the
buffer in its sentinel — and your subsequent `(buffer-live-p buf)`
returns nil with no obvious cause. Set
`(setq-local eat-kill-buffer-on-exit nil)` *before* `eat-exec` when
you want to inspect post-mortem state.

### Subprocess `(point-max)` grows on cosmetic redraws

Eat's `eat-update-hook` fires on every render — including ones
triggered by switching focus into the eat buffer (cursor blink,
status-line repaints, terminal-app focus events). Any classifier or
"is this idle?" heuristic that bumps a timestamp on hook fire will
spuriously flip rows to "active" simply because the user looked at
them.

The reliable signal for "process is producing real output" is a
**TUI-specific marker in the buffer tail** (e.g. Claude Code's
spinner string `esc to interrupt`), not buffer-size growth and not
hook-fire frequency.

### Sending input to a running TUI via `process-send-string`

The simplest way to programmatically inject input into a running eat
subprocess (REPL, claude, any other TUI) is `process-send-string` on
the buffer's process — *not* simulated key events, *not* `insert` into
the eat buffer. Pattern, lifted from `claude-dashboard.el`:

```elisp
(let ((proc (get-buffer-process eat-buffer)))
  (when (and proc (process-live-p proc))
    (process-send-string proc (concat message "\n"))))
```

The trailing `\n` triggers submit. The bytes flow through the master
PTY and are read by the TUI's stdin loop the same way real keystrokes
would arrive — no eat-internal hooks involved, no race with eat's
render pipeline. This is the supported path for "send a slash command"
or "drop a follow-up message into a busy agent" workflows.

**Caveats:**

- **The submit char must arrive in a separate PTY write** for some
  TUIs — Claude Code in particular. Sending `"text\r"` (or `"text\n"`)
  as a single string lands in the input box but **does not submit**:
  the TUI batches the read into one logical input event and treats the
  CR/LF as a literal newline-in-input. The fix is to write the body
  first, sleep ~50ms, then write a lone `"\r"`:

  ```elisp
  (process-send-string proc message)
  (sit-for 0.05)
  (process-send-string proc "\r")
  ```

  This pattern works for Claude Code, and is safe for most other TUIs
  (a separate Enter keypress is the most-faithful simulation of typing
  anyway). The 50ms gap lets Claude consume the first read before the
  CR shows up; without it, the two writes can coalesce in the kernel
  buffer and you're back to the single-read failure mode.

  **Slash commands are an exception** — `(format "/name %s\n" slug)`
  in one write *does* submit because the slash-command parser consumes
  `\n` directly. So existing patterns like the package's auto-name
  injection look like they "should work" with a single write and lull
  you into thinking plain text will too. It won't.

- **Multi-line content needs additional care.** Even with the
  split-write submit, embedded `\n` in the body may be interpreted as
  shift-enter (newline in input, no submit) or as multiple submits,
  depending on the TUI. For multi-line, the safer approach is
  bracketed-paste mode if available (`\e[200~...\e[201~` around the
  body, then `\r`); test against the specific TUI before relying on
  any pattern.

- **Defer when the TUI is busy.** If the agent is mid-tool-call, your
  injected message can interleave with in-flight output. Read whatever
  busy/idle signal the package exposes (`claude-dashboard--status`
  returns `running` / `idle` / `exited` based on a spinner regex in the
  buffer tail) and either defer 5–30s on `running`, or back off and
  retry. Don't synchronously poll — schedule the retry with
  `run-at-time`.

- **Process may have died between checks.** Always re-check
  `(process-live-p proc)` immediately before sending; the gap between
  "I picked this target" and "I'm sending now" can be arbitrarily long
  (especially with timers).

### Force `TERM` for an eat subprocess

Three options, in order of cleanliness:

1. `setq-local eat-term-name` (after `eat-mode`, before `eat-exec`).
2. Wrap the command in `env`: `(eat-exec buf name "env" nil
   (cons "TERM=xterm-256color" full-cmd))`.
3. Let-bind `process-environment`: `(let ((process-environment …))
   (eat-exec …))` — this works for `make-process` but eat layers
   its own TERM logic on top, so `eat-term-name` is the
   authoritative place.

## Process-survival multiplexers (`screen` vs `dtach`) — and when not to

When you need a PTY-using subprocess (claude, a TUI repl, a long
shell session) to outlive Emacs, the PTY master must be owned by
something other than Emacs. Pure `nohup` / `setsid` / `disown`
**don't work** — the issue isn't SIGHUP, it's that closing the
master PTY makes the slave's reads return `EIO`.

Two practical wrappers, both single-binary. **Important**: in
practice both introduced enough visual artifacts and per-keystroke
latency to a TUI agent like Claude Code that wrapping was worse
than the survival benefit.  When the user's complaint is "the
buffer feels weird / has artifacts", the right move is usually to
back out the wrapper and accept that the process dies on Emacs
exit.  Document this trade-off explicitly before sinking time into
either wrapper.

### GNU `screen`

- **Launch detached**: `screen -dmS NAME claude args`.
- **Attach from eat**: `screen -x NAME` (multi-attach; `-r` for
  exclusive reattach).
- **Kill cleanly**: `screen -S NAME -X quit`.
- **Check existence**: `screen -S NAME -Q select .` (exit 0 if alive).

Pitfalls:

- Needs `TERM=xterm-256color` (see eat section above) — eat-256color
  is rejected with `"Clear screen capability required"`.
- Has its own status-line / caption / hardstatus that you may want
  to suppress with a minimal `.screenrc` (`caption off`, `hardstatus
  ignore`).
- The escape key (`C-a` by default) intercepts your bindings; remap
  with `escape ^Pp` or pass `-e ^Pp`.
- Re-renders the buffer through its own emulator — rare ANSI
  sequences (window title OSC, OSC 4 colour queries) get consumed.
  TUI apps that drive cursor positioning aggressively can show
  visible repaint flicker.

### `dtach`

- **Launch detached**: `dtach -n SOCKET -E -r winch claude args`.
  `-E` disables the detach key entirely (so eat sees every
  keystroke); `-r winch` redraws by sending SIGWINCH on attach
  (works for any TUI that responds to resize, including claude).
- **Attach from eat**: `dtach -a SOCKET -E -r winch`.
- **Kill cleanly**: `pgrep -f "dtach.*SOCKET" | xargs kill -TERM`,
  then `rm SOCKET`.
- **Check existence**: `pgrep -f "dtach.*SOCKET" >/dev/null` — the
  socket file alone is not a reliable signal because it can linger
  after the dtach process dies.

Smaller / less intrusive than screen for the bare detach-and-attach
use case (no status line, no escape key, transparent ANSI
passthrough, no TERM gymnastics).  But its redraw model
(`-r winch` triggers SIGWINCH; `-r ctrl_l` sends `C-l`) means a TUI
that has *already* scrolled past important state on the master PTY
won't be able to re-paint it on a fresh attach — eat will see only
what arrives after the SIGWINCH-triggered repaint.  In practice
this caused enough perceived staleness that we removed it too.

### A subtle bug with backgrounded test commands

When testing multiplexer integrations via the Bash tool (which runs
shells without a TTY), `screen -x` / `dtach -a` will appear to
"silently fail" — the eat buffer flashes and dies because the attach
process exited immediately. The test setup, not your code, is at
fault. Reproduce inside the live Emacs daemon (`emacsclient --eval`
attached to a real frame) before chasing fixes.

## Time parsing: `encode-time` DST handling

When converting a user-supplied `YYYY-MM-DD HH:MM` string into an
encoded time via `encode-time`, the DST slot in the decoded list
matters:

```elisp
;; 9-element form: (SECOND MINUTE HOUR DAY MONTH YEAR DOW DST ZONE)
(encode-time (list 0 30 14 2 5 2026 nil nil nil))   ; ← BUG: DST=nil
(encode-time (list 0 30 14 2 5 2026 nil -1  nil))   ; ← right
```

`DST = nil` forces "**not** in DST" — for an in-DST date this shifts
the result by one hour relative to what the user typed. `DST = -1`
tells `encode-time` to figure out the correct offset for the given
date (DST or not) using the local timezone rules. The `t` value
forces "is in DST" and is symmetrically wrong for non-DST dates.

The bug is invisible during summer testing of summer dates, or winter
testing of winter dates — it only manifests when the parsed date and
the test date are on opposite sides of a DST transition. Symptom:
"the time I scheduled fired exactly one hour off." Always pass `-1`
unless you have a specific reason not to.

For HH:MM-today parses, you can avoid the DST question entirely by
copying the zone offset from `(decode-time (current-time))`:

```elisp
(let ((d (decode-time (current-time))))
  (encode-time (list 0 m h
                     (decoded-time-day d)
                     (decoded-time-month d)
                     (decoded-time-year d)
                     nil nil
                     (decoded-time-zone d))))    ; ← numeric ZONE wins
```

When ZONE is a number (UTC offset in seconds), `encode-time` takes the
list literally and ignores DST. This is fine for "same day, same
zone" arithmetic.

## Project-aware REPL naming: compare project roots, not directories

When wiring up "one REPL per project" by advising
`python-shell-get-process-name` (or any analogous "where do I send code?"
resolver in another language mode), the natural collision check is *"is
there a live REPL with the same target name rooted at a different
project?"*. The trap: people often write that check as

```elisp
;; WRONG — false-positives constantly
(with-current-buffer existing
  (not (file-equal-p default-directory new-root)))
```

A REPL's `default-directory` is wherever it was *launched*, not the
project root. So a REPL started from `~/projects/foo/examples/` keeps
`default-directory = ~/projects/foo/examples/`, never the project root
`~/projects/foo/`. Comparing dirs against root → always different →
collision detected → advice falls back to the path-suffixed name → you
get `*foo*` *and* `*foo<~/projects/foo/>*` as parallel REPLs for the
same project, with `python-shell-send-string` non-deterministically
picking one or the other.

The fix is to compare *project roots* on both sides:

```elisp
(with-current-buffer existing
  (let ((other-proj (project-current nil)))
    ;; Conservative: no project on the existing buffer counts as a
    ;; "different project" (fall back to path-suffixed name) so a REPL
    ;; rooted in /tmp doesn't quietly intercept project sends.
    (or (null other-proj)
        (not (file-equal-p (project-root other-proj) new-root)))))
```

**Diagnosis**: if you're seeing two parallel REPLs with names like
`*<project>*` and `*<project><<root>>*`, both rooted in the same project,
that's this bug. Inspect the advice's body, swap the dir comparison for
`project-root` on both sides, kill one of the duplicate REPLs, and
re-send to confirm the resolver picks the canonical one.

This gotcha generalizes beyond python.el — same shape applies to any
"find the REPL for this buffer" function that compares paths.

## Working with Claude Code (the `claude` CLI) from Elisp

The `claude` binary is Bun-compiled — a single-file ELF with the JS
bundle linked in. Most of the operational quirks fall out of two
facts: it's a TUI app reading raw PTY input, and it has its own
on-disk state separate from the conversation flow.

### Per-session and per-PID state on disk

```
~/.claude/projects/<encoded-cwd>/<sid>.jsonl   # full transcript
~/.claude/sessions/<PID>.json                  # live name + metadata
~/.claude/settings.json                        # user-level config
```

- **`<encoded-cwd>`** maps the launch directory by replacing `_` and
  `/` with `-`. So `/home/amunoz/projects/nahual_models` becomes
  `-home-amunoz-projects-nahual-models`. This affects path
  construction when you want to read transcripts from elisp.

- **The transcript JSONL** is one JSON object per line. `type` ∈
  `{user, assistant, system}`; `system` events have subtypes like
  `compact_boundary`, `informational`, `local_command`,
  `turn_duration`, `custom-title`. The `customTitle` event records
  every `/name` and `/rename` — bottom-up traversal gives the most
  recent.

- **Per-PID `sessions/<PID>.json`** holds the *live* session name
  (set by `/name`/`/rename`). This is the source of truth for the
  current name; the transcript's `customTitle` may be stale from
  earlier renames. claude-dashboard reads PID-json first, falls back
  to transcript scan.

### Limit-reached events are NOT in the JSONL

When claude hits a usage limit (5-hour session, weekly, Opus/Sonnet,
or overage), the warning is rendered into the TUI but **not**
persisted to the transcript. Detection requires buffer scanning, not
transcript scanning. Authoritative regexes (extracted from the
bundled binary at `/nix/store/.../claude-code-X.Y.Z/bin/.claude-unwrapped`):

- `Approaching <kind> · resets <when>` — `·` is U+00B7, the lazy
  capture for `<when>` runs to the next `·` or EOL.
- `You've used <pct>% of your <kind> · resets <when>` — same shape.
- `usage limit reached — check plan` — the rejected (429) state, em
  dash is U+2014.

`<kind>` ∈ `{session limit, weekly limit, usage limit, extra usage
limit, Opus limit, Sonnet limit}`. The internal enum is
`{five_hour, seven_day, seven_day_opus, seven_day_sonnet, overage}`
mapped to the friendly labels via the bundle's `SE1` map.

### Reading the bundled binary for canonical strings

When upstream docs are silent on a TUI string, `grep -aoE` against
the unwrapped binary surfaces the literal templates:

```bash
UNW=/nix/store/<hash>-claude-code-X.Y.Z/bin/.claude-unwrapped
timeout 60 grep -aoE '[[:print:]]{0,80}<phrase>[[:print:]]{0,200}' "$UNW" \
  | sort -u | head -20
```

The wrapper at `bin/claude` is a small launcher; the actual JS bundle
is in `bin/.claude-unwrapped` (~237 MB). Strings come back surrounded
by JS code, but enough context is visible to identify the format
template.

### TUI submission: split-write or single-write?

Already covered in the eat section above ("Sending input to a running
TUI via `process-send-string`"). Recap of the Claude-specific rules:

- **Plain text input**: split-write only. Body, sit-for ~50ms, lone
  `"\r"`. A single concatenated write of `"<msg>\r"` fills the input
  box but never submits — Claude treats the read as one logical
  event with embedded CR.
- **Slash commands**: single write of `"/name <slug>\n"` works
  because the slash-command parser consumes the LF directly. This
  is the *only* case where the single-write pattern is reliable.

### Slash-command autocomplete defense (when injecting `/<command>` over the PTY)

Claude's input layer binds `tab` → `autocomplete:accept`,
`escape` → `autocomplete:dismiss`. The slash-command picker activates
on a leading `/` in the input and *competes with submit* — `\r` while
the picker is open may select-and-execute a different completion
than you intended (or none at all if the picker is in a stale state
from prior input).

To inject a slash command reliably from Elisp:

```elisp
;; 1. Dismiss any picker / autocomplete that might be open.
(process-send-string proc "\e")          ; ESC
(sit-for 0.1)
;; 2. Clear the input line in case there's leftover text.
(process-send-string proc "\C-u")
(sit-for 0.05)
;; 3. Send the FULL command name as one write — partial writes
;;    (`/r' then `ename') would trigger the picker mid-stream.
(process-send-string proc (format "/rename %s" new-name))
(sit-for 0.05)
;; 4. Submit in a separate write (split-write rule).
(process-send-string proc "\r")
;; 5. Wait for the command to land before doing anything else.
(sit-for 0.5)
```

The 0.5s tail wait matters when a follow-up step reads state that
the slash command modifies — e.g., `/rename` updates
`~/.claude/sessions/<PID>.json`'s `name` field, but only after the
TUI processes the submit. Reading the new name immediately after the
submit can return the old value.

claude-dashboard's `claude-dashboard--inject-rename` is this exact
pattern factored into a helper. Reuse it (or duplicate the shape)
whenever you're injecting a slash command — `/clear`, `/rename`,
`/permissions`, etc.

### Status / modal dismissal

Several slash commands open modal panels (e.g. `/status`, `/usage`,
`/help`). The footer reads `Esc to cancel`. To dismiss
programmatically:

```elisp
(process-send-string proc "\e")     ; ESC closes the modal
(sit-for 0.3)
```

`\C-u` does NOT dismiss the modal — it's input-line oriented. ESC is
the only reliable dismiss for modals. If you've sent text into the
input *and* a modal opened (e.g. by sending `/<command>` that
triggered the slash picker), you generally want ESC twice: once for
the picker, once for any modal it spawned.

### Spinner regex for "agent busy"

`claude-dashboard--status` matches `esc to interrupt` in the buffer
tail. That's the canonical "claude is processing" indicator. Don't
key on `eat-update-hook` fire frequency or `(point-max)` growth —
both fire on cosmetic redraws (cursor blink, focus events, status
line repaint) and produce false positives.

### Stable identity for "send to this session": SID, never buffer name

When scheduling a send/message to a specific claude session for later
delivery, the canonical identifier is the **session id** — not the
buffer name (renamed by `/name` / `/rename`), not the cwd (multiple
sessions can share one), not the eat process object (dies on
`--resume`).

```elisp
(or (and (fboundp 'claude-dashboard--live-session-id)
         (claude-dashboard--live-session-id inst))
    (claude-dashboard-instance-session-id inst))
```

Prefer `--live-session-id` (reads `~/.claude/sessions/<PID>.json`'s
`name`/sid fields, refreshed live by claude on every write) over the
cached struct field (which only updates on the package's refresh
tick).

**The fallback rule that matters in practice:** at enqueue time, a
freshly-launched session may have `sid = nil` because claude hasn't
yet written its first transcript line. Schedule entries store SID +
CWD; at fire time, when SID is nil/unmatched, fall back to the
**YOUNGEST** live instance in the matching CWD (sort by
`started-at` descending). A naive "first match in cwd" picks the
older sibling and quietly mis-routes the message.

### Welcome banner as a "ready" signal

After launch, claude renders a Welcome banner ending with the cwd:

```
│            /home/amunoz/projects/foo               │
╰─────────────────────────────────────────────────────╯

❯
```

Three useful properties:

- The banner appearing means the eat process is up and the agent has
  registered.
- The cwd in the banner verifies the launch hit the right directory
  (matches what you scheduled).
- The trailing `❯` (empty input box) signals "ready to receive
  input" — safe to inject the first message after a brief delay.

In practice, ~8s after launch is enough buffer for "claude has
initialized and shown the banner" on a fast machine. Pin the delay to
a defcustom (claude-dashboard uses
`claude-dashboard-pending-launch-followup-delay`) so it can be
tuned per machine.

### End-to-end smoke testing

When debugging schedule/send paths, a self-test that exercises the
full pipeline (launch → wait → followup-message → submit → response
match) catches more regressions than unit tests against single
functions. claude-dashboard ships
`M-x claude-dashboard-schedule-self-test` doing exactly this against
a disposable cwd; the same shape works for any custom send or launch
path. The test asserts:

1. The instance buffer registers under the expected cwd (launch
   completed).
2. The prompt text appears in the buffer history (submit worked,
   not just filled).
3. Some recognizable substring of the response is present (agent
   responded — proves the round-trip).

(2) is the one that catches the split-write regression specifically;
(1) and (3) catch other failure modes.

## `defcustom` doesn't reassign already-bound variables on reload

If your config or an earlier `load-file` set a variable, a later
`defcustom` for that variable in the same Emacs session **does not**
override the existing value. The variable retains its prior binding
and the defcustom changes are silently ignored.

To force a fresh default during interactive testing, `makunbound`
the variable and re-load:

```elisp
(makunbound 'my-package-foo-regexp)
(load-file "/path/to/my-package.el")
;; defcustom now sets the variable to its current default value
```

For end users, the only ways to pick up a new default are restart
Emacs or call `customize-set-variable` explicitly.

## `defvar` keymap bodies only run on first load

A common pattern:

```elisp
(defvar my-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "n" #'my-next)
    map))
```

The `let` body is only evaluated when the variable is unbound. On
subsequent `load-file`s the existing keymap is **kept verbatim** —
new bindings inside the `defvar` body are ignored. Two consequences:

- **Adding bindings**: hoist `define-key` calls *outside* the
  `defvar` so they run on every load:
  ```elisp
  (defvar my-mode-map (let ((map …)) … map))
  ;; These run unconditionally on every load:
  (define-key my-mode-map "w" #'my-copy-thing)
  ```
- **Removing bindings**: explicitly `(define-key map KEY nil)` in
  the unconditional section. A removed `define-key` inside the
  `defvar` body leaves the old binding live until Emacs restart.

## `font-lock-mode` strips manually-set face properties

When `font-lock-mode` is active in a buffer (default in many
modes), it considers `face` properties on text its territory.
Manually-applied `(propertize TEXT 'face 'foo)` gets cleared on the
next refontification — which can fire from many triggers (point
movement, redisplay).

In a buffer where you render UI by hand and don't want font-lock
involved, the cleanest fix is to disable it locally:

```elisp
(setq-local font-lock-defaults nil)
(font-lock-mode -1)
```

Setting `font-lock-defaults` alone isn't enough if `font-lock-mode`
was already enabled by the major-mode hook chain.

## magit-section: persisting visibility across re-renders

`magit-insert-section` accepts a third element in its type-form for
initial `hide` state:

```elisp
(magit-insert-section (my-section value t)   ; t = start hidden
  (magit-insert-heading "row")
  (insert "body\n"))
```

The `t` sets `(oref section hidden)` but **does not lay down the
invisibility overlay** until magit's own machinery applies it.
Applying it explicitly:

```elisp
(let ((sec (magit-insert-section (my-section v t) …)))
  (when (and sec (oref sec hidden))
    (magit-section-hide sec)))
```

To make fold state survive a buffer's `erase-buffer` + re-insert
cycle, set both:

```elisp
(setq-local magit-section-cache-visibility t)
(setq-local magit-section-initial-visibility-alist
            '((my-section . hide)))
```

`magit-section` keys cached visibility on the section's `value`,
so use a stable identity (a struct, an interned symbol, a string
that doesn't change between renders) — not a freshly-allocated
list per render.

## Fit-to-content side windows

When a buffer should occupy *only* the rows it needs (a status
dashboard, a notification strip, a small picker), the cleanest
combo is `display-buffer-in-side-window` plus
`(window-height . fit-window-to-buffer)`:

```elisp
(pop-to-buffer buf
               '((display-buffer-in-side-window)
                 (side          . bottom)
                 (slot          . 0)
                 (window-height . fit-window-to-buffer)
                 (preserve-size . (nil . t))))
```

Then re-run `fit-window-to-buffer` after every render so the
height tracks content as it changes:

```elisp
(when-let ((win (get-buffer-window buf 'visible)))
  (with-selected-window win
    (fit-window-to-buffer win nil min-height nil nil t)))
```

### Gotcha: `fit-window-to-buffer` is a no-op without a vertical sibling

It only resizes vertically when there's a vertically-stacked
sibling to absorb the freed lines. If your buffer ends up in a
window that's part of a left/right split (`window-combined-p win
nil` returns nil), `fit-window-to-buffer` silently does nothing
even though `count-screen-lines` correctly reports a small visible
height. The fix is to *force* the buffer into a vertical-split
context — `display-buffer-in-side-window` does this by definition
(it always docks against the frame edge).

### Invisible content doesn't count

`fit-window-to-buffer` calls `count-screen-lines (point-min)
(point-max)` which respects invisibility overlays. A buffer with
2222 raw lines but 9 visible-after-overlays lines fits to 9. Useful
when combining with magit-section folding.

## Custom `display-buffer` action functions

A `display-buffer` action function takes `(BUFFER ALIST)` and
returns the window it displayed in (or nil to chain to the next
action). Pattern for "reuse the window currently showing any
buffer matching predicate P":

```elisp
(defun my-reuse-window (buffer alist)
  "Reuse a frame window currently showing any buffer for which
my-buffer-matches-p returns non-nil."
  (when-let ((win (cl-find-if
                   (lambda (w)
                     (and (not (eq (window-buffer w) buffer))
                          (my-buffer-matches-p (window-buffer w))))
                   (window-list (selected-frame)))))
    (window--display-buffer buffer win 'reuse alist)
    win))

(setq my-window-action
      '((my-reuse-window display-buffer-pop-up-window)
        (inhibit-same-window . nil)))

(pop-to-buffer some-buf my-window-action)
```

Behaviour: if any window in the frame already shows a "matching"
buffer, swap the new buffer into that same window — no new window
created. Otherwise the next action in the list runs (here,
`display-buffer-pop-up-window` opens a fresh one).

This is the right primitive for "I want exactly one of these
buffers visible at a time" without tracking dedicated windows or
managing a slot manually.

## Crash-recovery manifest pattern (instead of process survival)

When the user wants "let me get back to my live agents after an
emacs crash" but you've concluded a real terminal multiplexer is
not worth the visual cost (see the screen / dtach section above),
the next-best option is a **manifest of resumable session
identifiers** + an explicit recovery command. Works whenever the
underlying agent has its own `--resume <sid>` mechanism that reads
state from disk (Claude Code does, mosh-server does, jupyter
notebooks do via their checkpoints, etc.).

### Skeleton

```elisp
(defcustom my-pkg-manifest-file
  (expand-file-name "manifest.el" my-pkg-state-dir)
  "Snapshot of currently-running sessions."
  :type 'file)

(defun my-pkg--write-manifest ()
  "Persist (cwd, session-id) for each live instance.  Idempotent."
  (when my-pkg-manifest-file
    (let ((entries
           (cl-loop for inst in (my-pkg--instances)
                    for cwd = (my-pkg-instance-cwd inst)
                    for sid = (my-pkg--resolve-session-id inst)
                    when cwd
                    collect (list :cwd cwd :sid sid
                                  :recorded (current-time)))))
      (let ((dir (file-name-directory my-pkg-manifest-file)))
        (when (and dir (not (file-directory-p dir)))
          (make-directory dir t)))
      (with-temp-file my-pkg-manifest-file
        (insert ";;; -*- lisp-data -*-\n")
        (let ((print-level nil) (print-length nil))
          (prin1 entries (current-buffer)))
        (insert "\n")))))

(defun my-pkg--read-manifest ()
  (when (and my-pkg-manifest-file
             (file-readable-p my-pkg-manifest-file))
    (with-temp-buffer
      (insert-file-contents my-pkg-manifest-file)
      (goto-char (point-min))
      (ignore-errors (read (current-buffer))))))

;;;###autoload
(defun my-pkg-resume-all ()
  "Relaunch every session in the manifest."
  (interactive)
  (let* ((entries (my-pkg--read-manifest))
         (live-cwds (mapcar #'my-pkg-instance-cwd (my-pkg--instances)))
         (cands (cl-loop for e in entries
                         for cwd = (plist-get e :cwd)
                         for sid = (plist-get e :sid)
                         when (and cwd sid (file-directory-p cwd)
                                   (not (member cwd live-cwds)))
                         collect (cons cwd sid))))
    (cond
     ((null entries) (message "manifest empty"))
     ((null cands) (message "nothing to resume"))
     ((y-or-n-p (format "Resume %d session(s)? " (length cands)))
      (dolist (c cands)
        (my-pkg--launch (car c) (list "--resume" (cdr c))))))))
```

### Hook the write into every state-changing event

Don't rely on a `kill-emacs-hook` write — it doesn't fire on hard
crashes, OOM kills, or `kill -9`. Instead write on *every* event
that changes the live instance set, plus a low-frequency
heartbeat:

```elisp
;; After registering a new instance:
(my-pkg--write-manifest)

;; In on-buffer-killed:
(my-pkg--write-manifest)

;; After enrichment fills in a session-id:
(my-pkg--write-manifest)

;; In the periodic refresh (5–30 s):
(ignore-errors (my-pkg--write-manifest))
```

The manifest is a small flat file; rewrites are cheap and the
filesystem is the persistence boundary that survives any kind of
emacs death.

### Recovery hygiene

- Skip entries whose cwd is gone (the project may have been moved
  or deleted while emacs was down).
- Skip sid-less entries (nothing to `--resume` against; they were
  written before enrichment finished).
- Skip cwds whose instance is *already running* in the current
  emacs (avoid duplicate-launch when the user partially restored
  manually before invoking the bulk command).
- Always confirm the count with `y-or-n-p` before bulk-launching —
  a stale manifest from weeks ago shouldn't fire 30 agents at
  once.
- **Never key on buffer name.** Buffer names get renamed live (claude
  -dashboard rewrites them on `/name`/`/rename`, magit retitles
  status buffers when the project moves, etc.) so today's
  `*claude-foo*` is tomorrow's `*claude-foo-deploy-fix*`. Use the
  agent's own session id (`sid`) as the primary key, fall back to a
  canonicalized cwd (`expand-file-name`). Both survive the renames
  the user actually does.

This pattern gives the user the ergonomics of "everything's still
there after a crash" with none of the PTY-wrapper artifacts. The
trade-off is that *in-flight tool execution* doesn't survive —
each resumed session gets a fresh PTY, the conversation continues
from disk but any tool call that was running mid-crash is gone.

## Working with `aio` / deferred packages (oauth2-auto, org-gcal)

OAuth flows via `oauth2-auto` are full of traps that took a long
session to map out. Most apply to any package built on `aio` /
deferred / synchronous waits for network callbacks.

### NEVER filter processes by `(eq (process-type p) 'network)`

The Emacs server itself is a network process (Unix-domain socket).
`(delete-process p)` on it kills the listener that accepts
emacsclient connections — the daemon survives with all buffers
intact, but you lose your only way to talk to it. The user has to
manually `M-x server-start` in an interactive frame to recover.

Filter precisely. To kill, e.g., only oauth2-auto's HTTP listener:

```elisp
(dolist (p (process-list))
  (when (and (process-name p)
             (string-prefix-p "oauth2-auto--httpd" (process-name p)))
    (delete-process p)))
```

Or filter by contact shape — TCP listeners have `(host PORT)` where
PORT is a number; Unix sockets have a path string. Skip anything
whose contact is a path.

### `aio-wait-for` blocks the main thread; emacsclient still works

When org-gcal's sync calls `aio-wait-for (oauth2-auto-access-token …)`,
the main loop sits in a busy-poll on `accept-process-output` until the
promise resolves. The interactive frames *appear frozen* (no keyboard
input processed) but `emacsclient --eval` calls still go through
because filter functions on the server's network process get fired by
`accept-process-output` itself. So you can diagnose / abort from
outside even when the user can't type in their frame.

Scheduling via `(run-at-time 0 nil #'foo)` does NOT escape this —
when the timer fires, `foo` runs on the same main thread and blocks
the same way. The only escapes are: aborting the wait, providing the
input it's waiting for, or killing the listener it's waiting on
(which raises an error and unwinds the chain).

### Capturing `browse-url` calls — set globally, not let-bound

To intercept a URL that the package would open in a browser (so you
can show it to the user over chat):

```elisp
(setq browse-url-browser-function
      (lambda (url &rest _)
        (setq afm/captured-oauth-url url)
        (with-temp-file "/tmp/captured-url.txt" (insert url))))
```

`let`-binding does NOT survive the aio yield. The package may call
`browse-url` deep inside a deferred chain, by which point your
`let` has gone out of scope. Use `setq` and restore later if needed.

Also use `defvar` (not just `setq`) to declare your capture variable,
because eval-elisp.sh runs each invocation in a fresh dynamic-binding
context and `(setq afm/x ...)` followed later by `(or afm/x ...)` can
trip "Symbol's value as variable is void" if you haven't `defvar`'d
it once.

### `read-string` blocks the requesting emacsclient

The manual-auth flow (`oauth2-auto-manually-auth = t`) prints a URL
and waits at `(read-string "Enter authorization code: ")`. If you
fired the sync via `bash scripts/eval-elisp.sh`, your script hangs
because emacsclient's request only returns after read-string does.
The user CAN type into the minibuffer in their interactive frame —
but if they don't notice it (focus is in a read-only buffer like an
`eat` Claude terminal), they may swear nothing happened.

**File-poller pattern** — let the user save the code to a file and a
timer feeds it into the minibuffer:

```elisp
(defvar afm/code-file "/tmp/oauth-code")
(defvar afm/poll-timer nil)
(when afm/poll-timer (cancel-timer afm/poll-timer))
(setq afm/poll-timer
      (run-with-timer
       2 2
       (lambda ()
         (when (and (file-exists-p afm/code-file)
                    (active-minibuffer-window))
           (let* ((raw (string-trim (with-temp-buffer
                                      (insert-file-contents afm/code-file)
                                      (buffer-string))))
                  ;; Defensive: strip "code=" / leading "=" / full URL
                  (code (cond
                         ((string-match "code=\\([^&[:space:]]+\\)" raw)
                          (match-string 1 raw))
                         ((string-prefix-p "=" raw) (substring raw 1))
                         (t raw))))
             (delete-file afm/code-file)
             (with-selected-window (active-minibuffer-window)
               (delete-minibuffer-contents)
               (insert code)
               (exit-minibuffer)))))))
```

The user — or you, via Bash — writes the code to `/tmp/oauth-code`
and the timer drops it into the prompt within 2s, no matter where
the user's cursor is.

### plstore + GPG for OAuth tokens on a gpg-less host

`oauth2-auto` persists tokens via Emacs's `plstore`, which encrypts
the secret section with GPG. Three settings have to line up or the
write hangs/errors:

1. `gnupg` package installed on the host (NixOS users on `age` may
   not have it — add it explicitly).
2. A GPG key for the user. For a daemon with no human present,
   generate one non-interactively without a passphrase:
   ```
   gpg --batch --pinentry-mode loopback --passphrase '' \
       --quick-generate-key "Emacs OAuth Tokens <you@example.com>" \
       default default 0
   ```
3. From Emacs:
   ```elisp
   (setq epa-pinentry-mode 'loopback)              ; never prompt for a passphrase
   (setq plstore-encrypt-to "you@example.com")     ; pin the recipient
   ```

Without `epa-pinentry-mode 'loopback`, `plstore-save` can hang
indefinitely on a pinentry dialog that has nowhere to display.
Without `plstore-encrypt-to`, plstore errors with
`(epg-error "no usable configuration" OpenPGP)`.

### Bypass when the package's own flow is too tangled

`oauth2-auto--plstore-write` has a long-standing bug where the
secret section ends up containing `t` placeholders instead of the
real token strings (reproduced on org-gcal). Pattern when this
happens: hand-roll the PKCE + token exchange and call `plstore-put`
directly.

```elisp
;; 1. PKCE pair we control
(let* ((charset "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
       (verifier (with-temp-buffer
                   (dotimes (_ 64) (insert (elt charset (random (length charset)))))
                   (buffer-string)))
       (challenge (base64url-encode-string
                   (secure-hash 'sha256 verifier nil nil t) t))
       (state (with-temp-buffer
                (dotimes (_ 12) (insert (elt charset (random (length charset)))))
                (buffer-string))))
  (setq afm/verifier verifier afm/state state)
  ;; ... construct google oauth URL with challenge ...
)

;; 2. After user supplies the code, exchange directly
(let* ((url-request-method "POST")
       (url-request-extra-headers
        '(("Content-Type" . "application/x-www-form-urlencoded")))
       (url-request-data
        (mapconcat (lambda (kv) (concat (url-hexify-string (car kv)) "="
                                        (url-hexify-string (cdr kv))))
                   `(("client_id"     . "...")
                     ("client_secret" . "...")
                     ("code"          . ,code)
                     ("code_verifier" . ,afm/verifier)
                     ("grant_type"    . "authorization_code")
                     ;; Default oauth2-auto manual-flow port is 8080, which
                     ;; collides with common local services (nginx). Pick a
                     ;; high port and use the SAME value as the redirect_uri
                     ;; you registered when constructing the auth URL.
                     ("redirect_uri"  . "http://localhost:28080"))
                   "&")))
  (with-current-buffer (url-retrieve-synchronously
                        "https://oauth2.googleapis.com/token" t t 30)
    (goto-char (point-min)) (re-search-forward "\n\n")
    (let* ((json-object-type 'plist) (json-key-type 'keyword)
           (response (json-read)))
      ;; 3. Write directly via plstore-put — NOT oauth2-auto--plstore-write
      (let ((ps (plstore-open (expand-file-name "oauth2-auto.plist"
                                                user-emacs-directory))))
        (plstore-put ps "%28%22primary%22%20org-gcal%29%0A"
                     nil  ; no public keys
                     (list :access-token  (plist-get response :access_token)
                           :refresh-token (plist-get response :refresh_token)
                           :expiration    (+ (float-time)
                                             (plist-get response :expires_in))))
        (plstore-save ps) (plstore-close ps)))))
```

Note `url-retrieve-synchronously` blocks the main thread — fine for
a one-off bootstrap call you initiate yourself; don't put it in a
hot path.

### Auth-code gotchas

- **OAuth codes are single-use.** Each `org-gcal-sync` retry creates
  a new flow with a new `state` and `code_verifier`. The user's
  pasted code only matches the LATEST flow. If they retry-paste a
  code from an earlier flow, exchange fails with `invalid_grant`.
- **"Malformed auth code"** = the code arrived at Google with a
  leading `=` or `code=` prefix (user copied the URL parameter
  instead of just the value). The poller stripping above handles
  this defensively.
- **`Quit` during "Contacting host: oauth2.googleapis.com:443"**
  aborts the token exchange and spends the code. Tell the user not
  to `C-g` once they see that line.
- **Multiple stacked sync flows.** Re-triggering sync before the
  previous one finished leaves orphaned listeners and `t`-stub
  plstore entries. Always `org-gcal--sync-unlock` and
  `clrhash oauth2-auto--plstore-cache` before re-triggering.

### Recovery commands

```elisp
(org-gcal--sync-unlock)               ; release sync mutex
(clrhash oauth2-auto--plstore-cache)  ; clear in-memory token cache
;; Wipe broken plstore file (forces re-decrypt or re-auth)
(let ((f (expand-file-name "oauth2-auto.plist" user-emacs-directory)))
  (when (file-exists-p f) (delete-file f)))
;; Abort any pending minibuffer prompt
(when (active-minibuffer-window) (ignore-errors (abort-recursive-edit)))
```

## Guard Rails

- **Never write to a file on disk while Emacs has it open** — use `insert`/`save-buffer` instead
- **Avoid `kill-buffer` without asking** — it's destructive and loses unsaved changes
- **Never `delete-process` by `process-type 'network` alone** — that includes the
  Emacs server's Unix-socket listener. Filter by `process-name` prefix or by
  contact shape (TCP listener has `(host PORT)` with numeric PORT; Unix sockets
  have a path string). Killing the server kills your only way to talk to the
  daemon; the user has to `M-x server-start` from an interactive frame to recover.
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
