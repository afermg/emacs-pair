# emacs-pair

This repository packages the `emacs-pair` skill for Claude Code, Pi, and Codex.

## Canonical skill entrypoint

The full skill instructions live in:

- `SKILL.md` at the repository root

That file is the entrypoint agents should read when this repo is installed as a skill or package. The canonical source file is `skills/emacs-pair/SKILL.md`; the root `SKILL.md` and `scripts/` are convenience symlinks so the repo root itself can be used as a skill directory.

## Maintenance notes

If you change packaging or installation behavior, keep these in sync:

- `README.md`
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

Use paths relative to the skill directory (`scripts/...`) in skill docs and examples.
