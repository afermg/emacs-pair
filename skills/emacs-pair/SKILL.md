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

- **`onChange`** — use for post-deploy fixups like permissions:
  `onChange = "chmod 600 $HOME/.msmtprc";`

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
