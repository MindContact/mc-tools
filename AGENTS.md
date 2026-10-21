# AGENTS.md

Public collection of standalone utility scripts. Anyone can read this repo:
no secrets, tokens, hostnames, client names or personal paths in commits.

## Layout

- One script per tool, at the repo root, executable (`chmod +x`).
- No shared libraries between scripts: each one must work when copied alone.
- Every new script gets a row in the README table and a short usage section.

## Script conventions

Follow `clean-caches.sh` as the reference:

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- Header comment: what it does, usage lines, what each target/option touches
  and what is lost. A reader must be able to decide whether to run it from
  the header alone.
- Default run (no arguments) is read-only: it shows what would happen.
  Destructive actions need an explicit argument.
- Machine-specific paths go in a variable near the top, overridable from env.
- Comments in English; messages printed to the user in Italian.
- Skip, don't break: if a target is in use by a running program, say so and
  move on.
- Check with `bash -n` (and `shellcheck` if available) before committing.

## Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), one tool per commit.
