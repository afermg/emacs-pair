# emacs-pair

A [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) that gives Claude full access to a running Emacs session via `emacsclient`. Read and write buffers, evaluate arbitrary Elisp, run M-x commands, and inspect editor state — all from your conversation with Claude.

## Prerequisites

An Emacs server must be running:

```
M-x server-start
```

Or add `(server-start)` to your init file.

## Installation

### As a plugin (recommended)

```bash
# Add the marketplace and install
/plugin marketplace add afermg/emacs-pair
/plugin install emacs-pair@afermg-emacs-pair
```

### Manual

Clone the repo and symlink the skill directory:

```bash
git clone https://github.com/afermg/emacs-pair.git
ln -s "$(pwd)/emacs-pair/skills/emacs-pair" ~/.claude/skills/emacs-pair
```

Then invoke it in Claude Code with `/emacs-pair`.

## What's included

- **`SKILL.md`** — The skill protocol that teaches Claude how to interact with Emacs: philosophy, common operations, Org mode recipes, error handling, and guard rails.
- **`scripts/discover-servers.sh`** — Discovers running Emacs server sockets and returns them as JSON.
- **`scripts/eval-elisp.sh`** — Evaluates Elisp expressions in a running Emacs server. Supports inline expressions (`-e`), files, and stdin/heredocs. Auto-discovers the server socket.

## Usage examples

Once the skill is active, Claude can:

- **Read buffers** — inspect file contents as Emacs sees them
- **Edit buffers** — insert, replace, or delete text through Elisp (preserving undo history)
- **Run commands** — execute any M-x command or Elisp function
- **Work with Org mode** — manage headings, agenda, clocking, and more
- **Debug** — read `*Messages*`, evaluate test expressions, inspect variables

## License

MIT
