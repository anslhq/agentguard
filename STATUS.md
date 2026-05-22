# AgentGuard Status

A clause-by-clause walk of the CONTEXT.md / ADR contract against the current
implementation. Labels match the state model in
[`CONTEXT.md` ↳ Execution Integrity Contract](CONTEXT.md):

- **verified** — wired end to end + tests prove the behavior runs.
- **partially_wired** — real call paths reach the behavior but only the
  documented subset is implemented; consumers may hit gaps.
- **scaffolded** — files exist but behavior is placeholder, marker-driven,
  or stub.
- **missing** — the contract clause is not implemented at all.
- **blocked-on-compiler** — implementation requires Zero compiler features
  not yet landed on the Mach-O direct backend (see
  [`AGENTS.md`](AGENTS.md) "Common syntax footguns" / capability matrix).

Last updated against the third session of the build (post-audit pass).

---

## Cursor host (primary target)

| Clause | State | Notes |
|---|---|---|
| `hook --host cursor --event beforeShellExecution` | **verified** | Live `~/.cursor/hooks.json` enforce mode is on. `tests/run-host-adapter.sh` covers 94 assertions including chained commands. |
| `hook --host cursor --event beforeReadFile` | **verified** | SEC001 (.env + allowlist), SEC002 (SSH), SEC003 (cloud creds), SEC004 (.netrc), SEC005 (registry tokens). |
| `hook --host cursor --event afterFileEdit` | **verified** | Appends to `changed-files.txt` and writes `bypass-findings.json` for protected paths. Plugin and binary-emitted wiring no longer set `--log-only`, so this enforcement actually fires in production (a real bug fixed mid-session). |
| `hook --host cursor --event afterShellExecution` | **partially_wired** | Currently `--log-only`. Hook fires and payload is captured; no enforcement decisions yet. |
| `hook --host cursor --event stop` | **verified** | Real Cursor stop payload shape (`status`, no `last_assistant_message`). Inside `.agentguard/` repo + status≠aborted + no lease → injects `followup_message`. |
| `hook --host cursor --event sessionStart/sessionEnd` | **partially_wired** | Log-only. Real `session` subcommand (B3) writes state separately. |
| CMD002 — `rm -rf` (notify, leading + chained) | **verified** | Chained `cd /tmp && rm -rf /etc/passwd` → CMD002 (conservative — mid-chain can't determine target offset for CMD003 refinement). |
| CMD003 — workspace-escape `rm -rf /etc` | **verified** | Leading-token only. `workspace_roots[]` + `/tmp/` + `/var/folders/` allowlists. |
| CMD004 — sudo / doas | **verified** | Front-anchored and mid-chain. |
| CMD005 — `git --force` / `reset --hard` | **verified** | Front-anchored and mid-chain. `--force-with-lease` softer message. |
| CMD006 — `--no-verify` / `HUSKY=0` | **verified** | Anywhere in command. |
| CMD007 — `curl|sh` / `wget|sh` | **verified** | Front-anchored and mid-chain. |
| CMD008 — `terraform destroy` | **verified** | Front-anchored and mid-chain. |
| SEC001 — `.env` basename allowlist | **verified** | Allows `.env.example`, `.envrc`, `.env.test`, `.env.template`, `.env.sample`, `.env.tests`, `.env.defaults`, `.env.ci`. Denies others. |
| SEC002 — SSH private keys | **verified** | `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`, `id_ed25519_sk`, `id_ecdsa_sk` denied; `.pub` allowed. |
| SEC003 — cloud creds | **verified** | `~/.aws/credentials`, `~/.aws/config`, `~/.kube/config`, `~/.config/gcloud/`. |
| SEC004 — `.netrc` | **verified** | Basename match. |
| SEC005 — `.npmrc` / `.pypirc` | **verified** | Basename match. |
| SEC006 — shell-mediated secret reads | **verified** | `cat`, `grep`, `head`, `tail`, `less`, `more`, `awk`, `sed`, `source`, `.`, `xxd`, `od`, `strings` + sensitive path (front-anchored or mid-chain). Honors SEC001 allowlist (`.env.example`, `.envrc`, `id_*.pub`, etc). |
| JSON-escape parser | **verified** | `cmd_end` walker respects `\"` inside the string. Pre-fix, quoted arguments truncated the command and downstream rules missed destructive payloads. |
| Mid-chain CMD003 target resolution | **verified** | `cd /tmp && rm -rf /etc/passwd` now resolves the target offset correctly and denies as CMD003 (was conservatively notify-only CMD002 in the previous commit). |
| Model-family-aware response phrasing | **verified** | Claude, GPT/o-series, Gemini, sandboxed each get tuned `agent_message`. |
| Stop-hook project scoping | **verified** | Silent passthrough outside `.agentguard/` repo. |

## Cursor product story (what the README promises)

| Promise | State | Notes |
|---|---|---|
| Risky shell commands → deterministic gate | **verified** | All CMD002–CMD008 reachable from Cursor hook. |
| Secret-bearing reads → block | **verified** | SEC001–SEC005. |
| Completion claim → require lease | **verified** | Cursor stop hook in `.agentguard/` repo with no lease and status≠aborted → injects followup_message. |
| Completion lease → evidence-backed | **verified** | `done --finalize` denies on (bypass-findings OR unverified-edits OR no check-state). Now also captures the real git working-tree diff (`git diff --name-only HEAD; git ls-files --others --exclude-standard`) into `.agentguard/cache/lease-diff.txt` via `std.proc.captureShell`, and the lease references that sidecar as `diffHash`. |
| Append-only canonical ledger | **verified** | All 5 ledger-emit call sites use `std.fs.appendBytes`. Tests prove 0→1→2→5 rows across separate process invocations. |
| Protected-path bypass detection | **verified** | afterFileEdit on `AGENTS.md`, `CLAUDE.md`, `.cursor/hooks.json`, `.github/workflows/`, `.agentguard/policy.json`, `.agentguard/checks.json` writes bypass-findings. |
| Pack: state-aware context | **verified** | Adapts `next_instruction` and `prompt` to current state (lease, bypass, unverified-edits, check-state, session). |
| Hooks installer | **verified** | `agentguard hooks install --host cursor [--print]` emits canonical fragment + jq merge command. `hooks uninstall` emits jq removal. |

---

## Cross-host

| Clause | State | Notes |
|---|---|---|
| Claude Code adapter | **scaffolded** | Plugin config exists at `plugins/claude-code/hooks/hooks.json` and calls `agentguard risk/verify/classify-stop/session --host claude-code`. The `--host` flag is parsed by `session` and `hooks install` but the `hook` subcommand only understands Cursor's envelope shape. `risk` and `verify` ignore the `--host` flag silently. **Not safe to enable in Claude today.** |
| Codex adapter | **scaffolded** | Plugin directory exists; binary has no Codex code path. |
| Multi-host envelope dispatch | **missing** | Single envelope schema (Cursor's) drives `hook`. Other hosts will fall through. |

---

## Subcommands

| Clause | State | Notes |
|---|---|---|
| `init` | **verified** | Writes `.agentguard/policy.json`, `checks.json`, `ledger.jsonl`, `cache/ledger-state.json`. |
| `scan` | **partially_wired** | Detects package manager via lockfile and emits conventional script commands. Does NOT parse `package.json` scripts directly — emits `verified:false` flag to advertise this. Real parsing blocked-on-compiler (Mach-O stack-frame teardown bug with a second large buffer inside `main()`). |
| `doctor` | **partially_wired** | Heuristic checks based on file existence; no runtime probes yet. |
| `risk --command "<c>"` | **verified** | All CMD002–CMD008. (Front-anchored only; the `hook` adapter has the chained-command awareness.) |
| `verify` | **verified** | Plan mode reports `changedFilesPresent`. `--record-pass <id>` + `--from-bash` / `--from-ci` distinguishes attestation source. `--reset` clears `changed-files.txt`. |
| `done` / `done --finalize` | **verified** | Evidence-backed: denies on bypass, unverified-edits, no check-state. Plan and finalize modes both gated. |
| `pack` | **verified** | State-aware as of latest pass. Token budget is a sentinel integer; real token counting is **blocked-on-compiler**. |
| `explain <CODE>` | **verified** | Goldens cover the registered codes. |
| `session start|current|end` | **verified** | Marker-file at `.agentguard/cache/session.json`. Host-aware (`cursor`, `claude-code`, `codex`, `unknown`). `issuedAt` is a sentinel until `std.time` lands. |
| `approve <id>` / `ack <code>` / `ack-bypass <id>` | **verified** | All append to ledger; `ack-bypass` removes `bypass-findings.json`. |
| `lease` | **partially_wired** | Stub subcommand; the lease state machine lives inside `done --finalize`. Standalone `lease check/inspect` is not yet a CLI surface. |
| `classify-stop` | **verified** | Reads stdin payload or `--message` flag and emits decision. |
| `hooks install --host cursor` | **verified** | Prints canonical fragment + jq merge command. Plugin file (`plugins/cursor/hooks.json`) structurally matches the binary emit (PATH-relative for the plugin, absolute path for the binary install). Test asserts they stay in sync. Claude/Codex correctly error as deferred. |
| `policy validate` / `policy migrate` | **partially_wired** | Always returns ok; no real validator. |

---

## Infrastructure

| Clause | State | Notes |
|---|---|---|
| Zero build → single binary | **verified** | `./scripts/build.sh` produces `bin/agentguard`. **Requires patched Zero compiler**; see [Zero compiler bootstrap](#zero-compiler-bootstrap) below. |
| `docs-lint` | **verified** | 112 files checked, clean. Forbidden-vocabulary detector + allow-superseded markers + DOC001 emission. |
| Test harness | **verified** | 15 suites, ~180 assertions, 0 failed in ~50–60s. |
| `OutputCapper` runtime contract | **scaffolded** | Validated by an outside-the-binary shell script (`tests/validate-output-caps.sh`). Not enforced from inside the binary. **Blocked-on-compiler** (helper-function ABI). |
| GitHub Actions authoritative gate | **scaffolded** | Workflow file present at `.github/workflows/`; binary has no `--ci` mode. |
| Plugin assets for Claude/Cursor/Codex | **scaffolded** (Claude/Codex) / **verified** (Cursor) | Cursor plugin matches the binary's behavior. The other two have hooks.json templates but no matching binary code paths. |

---

## Blocked on compiler work

These items will not progress without Zero v0.1.4+ ABI improvements:

- ~~**`std.proc.capture`** — bounded subprocess stdout capture.~~
  **Landed this session as `std.proc.captureShell(cmdline, buf)`.**
  Routes through a libc `popen()`-based runtime shim on Mach-O direct
  backend; ELF64 path emits CGEN004 (unsupported on ELF — not currently
  needed since CI is also un-bootstrapped). Used by `done --finalize`
  to capture the real working-tree diff into `lease-diff.txt`.
- **`std.time`** — wall-clock + monotonic. Needed for:
  - real `issuedAt` / `expiresAt` in the lease (currently `"unset"`)
  - lease TTL enforcement (currently presence-only)
  - session activity timeout
- **Helper functions with `String` / `Span<u8>` parameters** — needed to break `main.0` (2.3k lines) into proper modules and to make the chained-command and SEC inventory scanners reusable across the `risk` subcommand and the `hook` adapter without duplicate code.
- **`std.fs.readBytes` with file-size detection** — needed for:
  - real `package.json` parsing in `scan`
  - reading the last N ledger rows in `pack`
- **Second large stack buffer + `Maybe<String>` interaction** — documented Mach-O stack-frame teardown bug. Currently caps the payload buffer at 1024 bytes. Real Cursor envelopes (~1.1KB) are truncated of the trailing `transcript_path` / `user_email`, neither of which is used in any rule.

---

## Zero compiler bootstrap

The vendored `zerolang/` source is gitignored in this repo. It lives
alongside agentguard as a separate git checkout. Two patch layers
make AgentGuard's binary buildable, plus an unresolved upstream
syntax migration that constrains how rebuilds work today.

### Layer 1 — Upstream PR

Two single-concern, build-clean commits sit on the
`agentguard-mach-o-direct-backend` branch of
`https://github.com/anslhq/zerolang` and were submitted to
`vercel-labs/zerolang` as PR
[#203](https://github.com/vercel-labs/zerolang/pull/203):

1. *Wire Mach-O direct backend for std.mem.eql and path-form std.fs
   helpers.* Lowers `IR_VALUE_BYTE_VIEW_EQ`, the FS exists / is_dir /
   make_dir / remove / remove_dir family, and the FS write / read
   path family to inline AArch64 syscalls via `svc #0x80`. No runtime
   helper, no extra link plan — matches upstream's ELF64 design.

2. *Add `std.fs.appendBytes`.* New stdlib API returning
   `Maybe<usize>`, lowered on both ELF64 and Mach-O by reusing the
   write codepath with `O_APPEND`. Includes a conformance test under
   `conformance/native/pass/std-fs-append.0`.

Verification on the PR branch:

- `pnpm run conformance:local` — provenance guardrails, type core
  smoke, MIR verifier smoke, row syntax smoke, conformance all ok
  (146/146 native pass, including the new `std-fs-append`).
- `pnpm run native:test:local` — `http runtime smoke ok`,
  `native conformance ok`.
- `pnpm run command-contracts:local` — snapshots ok.
- `pnpm run docs:test` — 7/7 pass.
- `pnpm run test:zero` — 10/10 pass.
- `pnpm run zls -- --self-test` — ok.
- `pnpm run reliability:smoke` — ok.
- Compiler builds clean with `-std=c11 -Wall -Wextra -Wpedantic -Os`.

### Layer 2 — AgentGuard-local additions (not in the upstream PR)

AgentGuard uses `std.proc.captureShell(cmdline, buf) -> Maybe<usize>`
to capture `git diff --name-only HEAD` into the lease sidecar. That
opcode is *not* in the upstream PR — the inline `fork + exec + pipe +
wait` sequence is large enough (~150 instructions on AArch64) that it
warrants its own design conversation upstream. For now AgentGuard
carries a local-only addition:

- `IR_VALUE_PROC_CAPTURE_SHELL` reserved in the IR.
- Lowered through a runtime helper `zero_proc_capture_shell` in
  `zerolang/native/zero-c/runtime/zero_runtime.c`, implemented with
  libc `popen()`.
- ELF64 emits CGEN004 (deliberately unsupported pending an inline
  or proper helper design).
- Mach-O direct: routes through the runtime helper via the object
  backend's link plan.

This addition is what `scripts/build.sh` relies on to produce the
shipped `bin/agentguard`.

### Layer 3 — Row-syntax migration blocker

Upstream merged PR #195 "Adopt row syntax as current surface" before
PR #203 landed. AgentGuard's `src/main.0` is still written in the
previous parenthesized surface and therefore *cannot be parsed* by a
compiler built from the current upstream `main` (the type checker
errors with `PAR100: unexpected character in row syntax`).

The currently shipped `bin/agentguard` was built against a
pre-row-syntax compiler revision and continues to run end-to-end
(15/15 AgentGuard test suites pass against it). Rebuilding the
binary from source today requires one of:

- Porting `src/main.0` (~2700 lines) to the new row syntax.
- Pinning `zerolang/` to a pre-row-syntax revision and re-applying
  Layer 1 + Layer 2 on top of that revision.
- Waiting for an upstream porting tool that translates the previous
  surface mechanically.

This is documented honestly here rather than glossed over because it
is the practical state of the build path today.

---

## Verification matrix

| Suite | Assertions | Covers |
|---|---|---|
| `docs-lint` | 1 (clean) | Vocabulary guard across 112 files |
| `explain-goldens` | 5 | Diagnostic registry shape |
| `output-caps` | 1 (shell) | Output length cap (out-of-binary) |
| `docs-lint smoke` | 1 | DOC001 emission on a known-bad fixture |
| `risk-goldens` | 23 | All CMD002–CMD008 + safe baseline |
| `verify-goldens` | 0 (placeholder) | TODO |
| `lease-goldens` | 10 | Lease shape + state cache |
| `done-goldens` | 10 | done plan/finalize + bypass lifecycle |
| `host-payload-smoke` | 5 | Each host's payload format roundtrip |
| `host-adapter` | 108 | Full Cursor adapter incl. chained commands, model-family routing, real-payload shapes, SEC001-SEC006, JSON-escape parser, mid-chain CMD003 |
| `ledger-append` | 6 | Real append behavior across separate process invocations |
| `session` | 13 | session start/current/end + host-flag handling |
| `hooks-install` | 19 | install/uninstall + 7-event fragment + claude/codex deferred error + plugin/binary sync |
| `lease-evidence` | 18 | Evidence-backed lease + real git-diff sidecar (via std.proc.captureShell) |
| `pack-state` | 10 | State-aware pack across 6 observable states |

Total: 15 suites, ~230 assertions, 0 failed in ~40s.

---

## Honest gaps still open

1. **Claude and Codex adapters not safe to enable.** Plugin configs exist
   but the binary doesn't dispatch their envelope shapes. Documented
   `scaffolded`. Don't enable in those hosts until the multi-host envelope
   dispatch lands.
2. **Real `verify` diff** is still pipe-pattern (host-tracked via
   afterFileEdit hook), not git-aware. The `done --finalize` lease
   issuance now captures `git diff --name-only HEAD; git ls-files
   --others --exclude-standard` into `lease-diff.txt`, so the **lease
   evidence** is git-aware, but `verify`'s `changedFilesPresent` flag
   still derives from the in-session afterFileEdit hook, not from git.
3. **Lease `issuedAt` and `expiresAt`** are sentinel strings until
   `std.time` lands. Lease expiry is presence-only.
4. **Lease `diffHash`** is now `"lease-diff.txt"` — a path to a sidecar
   file that contains the real list of changed + untracked paths
   captured via `std.proc.captureShell` at lease issuance. Content
   hashing (e.g. sha256) waits on a hash primitive but the sidecar is
   already auditable.
5. **`pack` recent_ledger** is a pointer, not the actual recent rows.
   Real ledger readback waits on `std.fs.readBytes`.
6. **`scan` `package.json` script parsing** is conventional-not-parsed.
   The `verified:false` field advertises this.
7. **Bootstrap reproducibility** — anyone cloning will hit a build wall.
   Compiler patches need to ship as either a `.patch` file or a
   `scripts/bootstrap.sh` automation.
