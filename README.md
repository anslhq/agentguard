# AgentGuard

AgentGuard is a local-first control layer for agentic coding workflows.

It sits around tools like Cursor, Claude Code, and Codex and turns risky commands, code edits, and completion claims into deterministic checks with machine-readable output.

## Status

**Alpha, in active development.** [`STATUS.md`](STATUS.md) is the
clause-by-clause source of truth.

The Cursor host path is the primary target and is the most complete:

- Live-enforce wiring against the real Cursor hook payload shape (94
  host-adapter test assertions, including chained commands like
  `cd /tmp && rm -rf /etc/passwd`, real-world envelope shapes, model-family
  routing).
- 8 command-risk classes (CMD002–CMD008) and 5 secret-read classes
  (SEC001–SEC005) reach the Cursor adapter.
- Evidence-backed completion lease (`done --finalize` denies on bypass
  findings, unverified edits since last verify, or missing check-state).
- Append-only canonical ledger via a patched `std.fs.appendBytes`.
- Protected-path bypass detection wired through the `afterFileEdit` hook
  (edits to `AGENTS.md`, `CLAUDE.md`, `.cursor/hooks.json`,
  `.github/workflows/`, `.agentguard/policy.json`, `.agentguard/checks.json`
  raise a strong-confidence bypass finding that blocks the next lease).
- State-aware `pack` that adapts its `next_instruction` to the live state.
- Real `hooks install --host cursor` that emits a canonical
  fragment + `jq` merge command for `~/.cursor/hooks.json`.

The Claude Code and Codex host paths are **scaffolded** — plugin configs
exist but the binary doesn't yet route those envelope shapes. Do not enable
them in those hosts today. See `STATUS.md` for the full state of every
contract clause.

### Building from source today (important)

This repo's binary depends on a patched Zero compiler. There are two
patch layers:

1. **Two upstream-ready commits** on the `agentguard-mach-o-direct-backend`
   branch of `https://github.com/anslhq/zerolang`, submitted to
   `vercel-labs/zerolang` as PR
   [#203](https://github.com/vercel-labs/zerolang/pull/203):

   - *Wire Mach-O direct backend for std.mem.eql and path-form std.fs
     helpers.* Lowers `IR_VALUE_BYTE_VIEW_EQ`, the FS exists/is_dir/
     make_dir/remove/remove_dir family, and the FS write/read paths to
     inline AArch64 syscalls. No runtime helper, no extra link plan.
   - *Add `std.fs.appendBytes`.* New stdlib API with `Maybe<usize>`
     return, lowered on both ELF64 and Mach-O by reusing the write
     codepath with `O_APPEND`. Includes a conformance test.

2. **An AgentGuard-only local patch** (not in the upstream PR) that
   restores `std.proc.captureShell` and its runtime helper. AgentGuard
   uses it to capture `git diff --name-only HEAD` into the lease
   sidecar. Upstream's review of how to land shell-capture cleanly is
   still open, so AgentGuard maintains this as a local addition for
   now.

Upstream also migrated `.0` sources to a new "row" syntax. AgentGuard's
`src/main.0` is still written in the previous surface and therefore
cannot be rebuilt against the latest `zerolang/main` until it is
ported. The currently shipped `bin/agentguard` was built against a
pre-row-syntax compiler revision and continues to run end-to-end (all
15 test suites pass). Rebuilding from source today requires either
porting `main.0` to row syntax or pinning the local `zerolang/`
checkout to a pre-row-syntax revision plus the upstream PR commits.

If you run `./scripts/build.sh` against a stock `~/.zero/bin/zero`
without the patches applied, you'll hit `CGEN004: direct AArch64
Mach-O value kind is unsupported`. Against the latest upstream
without porting `main.0`, you'll hit `PAR100: unexpected character in
row syntax`.

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
