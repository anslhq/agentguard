# AgentGuard

AgentGuard is a local-first control layer for agentic coding workflows.

It sits around tools like Cursor, Claude Code, and Codex and turns risky commands, code edits, and completion claims into deterministic checks with machine-readable output.

## Status

**Alpha, in active development.**

This repository is being prepared in public while the core implementation is still landing. Today it contains:

- a working Zero-based CLI binary shape
- a documented product/design contract in `CONTEXT.md` and `docs/adr/`
- a tested vertical slice for parts of `risk`, `verify`, `done`, `classify-stop`, `explain`, and Cursor-style hook responses

It does **not** yet fully implement the entire AgentGuard contract described in the docs. In particular, some areas are still partial or stubbed:

- full diff-aware verification planning
- evidence-backed completion lease issuance
- append-only canonical ledger behavior
- fully wired Claude Code and Codex runtime adapters
- real context packing

If you want a finished, production-grade guardrail product today, this is not that yet. If you want to follow or contribute to the build-out of that system, this is the right repo.

## Executive Thesis

**AgentGuard is a local-first control layer for agentic coding workflows.**

It sits between coding agents and the repository they operate on. It does not try to replace Cursor, Claude Code, Codex, GitHub Copilot, Gemini CLI, or MCP-based tooling. It tries to make those systems safer and more reliable by turning risky commands, code changes, and completion claims into deterministic checks.

The core thesis is simple:

> Agents are getting very good at writing code, but the workflow around them is still weak.

AgentGuard is meant to turn the messy loop of:

```text
agent edits
maybe runs checks
maybe forgets
maybe overclaims completion
human reconstructs what happened
```

into a structured control loop:

```text
classify risk
verify changes
package focused context
produce the next instruction
record the run
```

## Why This Exists

The product is aimed at a real workflow gap in modern agentic coding:

- agents can modify the wrong files
- agents can skip the right checks
- agents can introduce dependency, CI, infra, or auth risk casually
- agents can overclaim completion
- teams can lose the thread in long multi-turn coding sessions

The problem is not just prompt quality. The problem is missing control around the prompt.

## What AgentGuard Is

AgentGuard is designed to answer four questions in an agentic coding loop:

1. Should this command be allowed before it runs?
2. What checks are required after these edits?
3. Can the agent legitimately claim completion yet?
4. What is the next scoped instruction if the answer is no?

The long-term shape is:

- `agentguard risk` for pre-command classification
- `agentguard verify` for post-edit verification planning and check recording
- `agentguard done --finalize` for evidence-backed completion leases
- `agentguard classify-stop` for stop-hook enforcement of completion claims
- `agentguard pack` for compact, grounded context handoff

In that sense, AgentGuard is best thought of as **deterministic agent middleware** for coding workflows.

## Why Zero

AgentGuard is intentionally built in [Zero](https://github.com/vercel-labs/zerolang), an experimental language aimed at agent-facing tooling.

That matters here because AgentGuard wants:

- deterministic CLI behavior
- JSON-first output
- stable diagnostic codes
- low-dependency local execution
- no Node runtime requirement for the core binary

This repo may carry a local `zerolang/` checkout during development, but that clone is **local-only reference/tooling** and is **not part of the AgentGuard project artifact**. It exists to support local compiler experiments and Darwin build work while the Zero toolchain is still evolving.

## Product Principles

- Do not replace the agent. Control the loop around it.
- JSON is the contract. Text is presentation.
- Prefer deterministic checks over prompt-only policy.
- Fail loudly when the agent is about to do something risky.
- Prefer targeted verification over "run everything."
- Every failure should produce a next action.
- Keep context small, grounded, and current.
- Make bypasses visible instead of pretending they cannot happen.
- Local hooks are convenience. CI is authority.

## Repository Layout

- `src/main.0` — current CLI implementation
- `CONTEXT.md` — canonical product/domain contract
- `docs/adr/` — architectural decisions
- `plugins/` — host integration assets for Claude Code, Cursor, Codex, Git hooks, and GitHub Actions
- `tests/` — shell-based golden and smoke tests
- `scripts/build.sh` — local Darwin build path
- `runtime/zero_runtime.c` — small C runtime shim used on Darwin builds
- `zerolang/` — optional local development/reference clone only; not shipped as part of AgentGuard

## Build From Source

### Prerequisites

- macOS or Linux
- `git`
- `jq`
- Zero available locally for development builds

### Local build

On macOS Darwin, the current development path is:

```sh
make -C zerolang/native/zero-c
./scripts/build.sh
```

If you do not have a local `zerolang/` clone yet, the current repository does not provide a polished bootstrap flow for that. For now, this is a contributor/developer setup step rather than part of the published end-user install path.

That produces:

```text
bin/agentguard
```

### Verify the current implementation

Run the repo test harness:

```sh
./tests/run-all.sh
```

This validates the currently landed slice. It should not be read as proof that the full product spec is complete.

## Current CLI Surface

Today the binary exposes these commands:

```text
risk
verify
done
pack
scan
init
doctor
explain
session
approve
ack
ack-bypass
lease
classify-stop
hook
policy
```

Some of these are already meaningful, some are partial, and some are present mainly to hold the eventual contract stable while implementation catches up.

## Development Principles

AgentGuard is opinionated about execution integrity:

- do not claim completion without evidence
- keep the host contract machine-readable
- prefer deterministic checks over prompt-only policy
- make bypasses visible instead of pretending they cannot happen
- keep repo policy versioned and reviewable

The source-of-truth design lives in `CONTEXT.md`. If code and README disagree, `CONTEXT.md` and the ADRs win.

## Roadmap

Near-term work focuses on closing the gap between the documented contract and the shipped runtime:

- real diff-hash and stale-check handling
- real attestation-aware lease issuance
- append-only ledger semantics
- first fully wired host integration path
- installation UX and release packaging
- top-level OSS CI and release automation

## Contributing

Contributions are welcome, especially around:

- deterministic CLI/runtime behavior
- fixture coverage
- host adapter correctness
- docs/spec reconciliation
- build and release ergonomics

Start with `CONTRIBUTING.md`.

## Security

This project is alpha software and should not be treated as a trusted security boundary yet. See `SECURITY.md`.

## License

MIT, see `LICENSE`.
