# emacs-pair

A Claude Code, Pi, and Codex skill that gives your coding agent full access to a running Emacs session via `emacsclient`. Read and write buffers, evaluate arbitrary Elisp, run M-x commands, and inspect editor state — all from your conversation.

## Prerequisites

An Emacs server must be running:

```
M-x server-start
```

Or add `(server-start)` to your init file.

## Installation

### Claude Code

#### As a plugin (recommended)

```bash
# Add the marketplace and install
/plugin marketplace add afermg/emacs-pair
/plugin install emacs-pair@afermg-emacs-pair
```

#### Manual

```bash
git clone https://github.com/afermg/emacs-pair.git
ln -s "$(pwd)/emacs-pair/skills/emacs-pair" ~/.claude/skills/emacs-pair
```

Then invoke it in Claude Code with `/emacs-pair`.

### Pi

Pi can install this repo directly as a local or git package:

```bash
pi install ~/projects/emacs-pair
# or
pi install git:git@github.com:afermg/emacs-pair.git
```

You can also expose it as a plain skill directory:

```bash
mkdir -p ~/.pi/agent/skills
ln -s ~/projects/emacs-pair ~/.pi/agent/skills/emacs-pair
```

If you already keep skills under `~/.codex/skills`, Pi can load them from there too by adding that directory to `~/.pi/agent/settings.json`.

### Codex

Codex can use the repo root directly as a skill directory:

```bash
mkdir -p ~/.codex/skills
ln -s ~/projects/emacs-pair ~/.codex/skills/emacs-pair
```

The repo root intentionally mirrors the canonical skill layout so `SKILL.md`, `CLAUDE.md`, and `scripts/` all resolve correctly when symlinked this way.

## What's included

- **`SKILL.md`** — The skill protocol that teaches the agent how to interact with Emacs: philosophy, common operations, Org mode recipes, error handling, and guard rails.
- **`scripts/discover-servers.sh`** — Discovers running Emacs server sockets and returns them as JSON.
- **`scripts/eval-elisp.sh`** — Evaluates Elisp expressions in a running Emacs server. Supports inline expressions (`-e`), files, and stdin/heredocs. Auto-discovers the server socket.

## Usage examples

Once the skill is active, your agent can:

- **Read buffers** — inspect file contents as Emacs sees them
- **Edit buffers** — insert, replace, or delete text through Elisp (preserving undo history)
- **Run commands** — execute any M-x command or Elisp function
- **Work with Org mode** — manage headings, agenda, clocking, and more
- **Debug** — read `*Messages*`, evaluate test expressions, inspect variables

## License

MIT

## Acknowledgements

This project was inspired by [marimo-pair](https://github.com/marimo-team/marimo-pair).

See also: [efrit](https://github.com/steveyegge/efrit) by Steve Yegge, an earlier Emacs-native AI coding assistant that runs Claude inside Emacs itself rather than driving it from an external process.
