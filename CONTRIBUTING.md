# Contributing to AgentGuard

Thanks for contributing.

## Before you start

AgentGuard is currently an **alpha** project. The design contract is ahead of the implementation in some areas, so contributors should work carefully from the documented source of truth.

Read these first:

1. `CONTEXT.md`
2. `docs/adr/`
3. `AGENTS.md`

If code and README disagree, prefer `CONTEXT.md` and the ADRs.

## What kinds of contributions are useful

Good contributions right now:

- closing gaps between the documented contract and the runtime
- expanding fixture and golden coverage
- tightening host adapter behavior
- improving build/release ergonomics
- improving docs accuracy

Less useful right now:

- speculative abstractions
- big refactors unrelated to the current product contract
- marketing claims that overstate implementation completeness

## Development setup

Current contributor setup is local and a little manual.

### Requirements

- macOS or Linux
- `git`
- `jq`
- a local Zero toolchain available for development builds

### Build

```sh
./scripts/build.sh
```

### Test

```sh
./tests/run-all.sh
```

## Working style

- Keep changes surgical.
- Do not silently broaden scope.
- Do not mark partially wired behavior as complete.
- Preserve the terminology in `CONTEXT.md`.
- Prefer adding fixture coverage when changing command/output behavior.

## Docs changes

This repo treats vocabulary drift as a real bug.

Run:

```sh
./bin/docs-lint
./tests/run-docs-lint-smoke.sh
```

when you touch `CONTEXT.md`, ADRs, or project docs.

## Pull requests

A good PR for AgentGuard should include:

- what changed
- whether the change is `verified`, `partially_wired`, or still `scaffolded`
- what tests or smoke checks were run
- any remaining gaps or caveats

## Security and trust boundaries

Do not describe AgentGuard as a hard security boundary unless the relevant behavior is actually implemented and verified.

This project is about deterministic workflow control, but it is still early-stage software.
