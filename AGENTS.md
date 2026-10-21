# AGENTS.md

Public collection of standalone utility scripts. Anyone can read this repo:
no secrets, tokens, hostnames, client names or personal paths in commits.

## Layout

- One folder per tool (`<tool>/<tool>.sh`, executable), holding its
  `.env.example` and, locally, its git-ignored `.env`.
- No shared libraries between tools: each folder must work when copied alone.
- Every new script gets a row in the README table and a short usage section.

## Script conventions

Follow `clean-caches/clean-caches.sh` as the reference:

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- Header comment: what it does, usage lines, what each target/option touches
  and what is lost. A reader must be able to decide whether to run it from
  the header alone.
- Default run (no arguments) is read-only: it shows what would happen.
  Destructive actions need an explicit argument.
- Machine-specific paths and settings come from `.env` (git-ignored), loaded
  from the script's own directory; each has a generic default in the script
  and is documented in `.env.example`. Never commit `.env`.
- Everything in English: comments, messages, docs.
- Skip, don't break: if a target is in use by a running program, say so and
  move on.
- Check with `bash -n` (and `shellcheck` if available) before committing.

## Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), one tool per commit.
