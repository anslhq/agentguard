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
| `hook --host cursor --event afterFileEdit` | **verified** | Appends to `changed-files.txt` and writes `bypass-findings.json` for protected paths. |
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
| Model-family-aware response phrasing | **verified** | Claude, GPT/o-series, Gemini, sandboxed each get tuned `agent_message`. |
| Stop-hook project scoping | **verified** | Silent passthrough outside `.agentguard/` repo. |

## Cursor product story (what the README promises)

| Promise | State | Notes |
|---|---|---|
| Risky shell commands → deterministic gate | **verified** | All CMD002–CMD008 reachable from Cursor hook. |
| Secret-bearing reads → block | **verified** | SEC001–SEC005. |
| Completion claim → require lease | **verified** | Cursor stop hook in `.agentguard/` repo with no lease and status≠aborted → injects followup_message. |
| Completion lease → evidence-backed | **verified** | `done --finalize` denies on (bypass-findings OR unverified-edits OR no check-state). |
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
| `hooks install --host cursor` | **verified** | Prints canonical fragment + jq merge command. Claude/Codex correctly error as deferred. |
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

- **`std.proc.capture`** — bounded subprocess stdout capture. Needed for:
  - real `git diff` + content-hashed `diffHash` in the lease
  - `verify` running gated checks itself
  - `--ci` mode
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

The vendored `zerolang/` source is gitignored. The binary uses a custom-patched
compiler that adds these opcodes to the darwin-arm64 Mach-O direct backend:

- `IR_VALUE_BYTE_VIEW_EQ` — `std.mem.eql` on byte views
- `IR_VALUE_FS_EXISTS` (and FS_IS_DIR / FS_MAKE_DIR / FS_REMOVE / FS_REMOVE_DIR)
- `IR_VALUE_FS_WRITE_PATH` / `IR_VALUE_FS_WRITE_BYTES_PATH`
- `IR_VALUE_FS_READ_PATH`
- `IR_VALUE_FS_APPEND_BYTES_PATH` *(this session)*

The opcodes route to a small C runtime shim at `runtime/zero_runtime.c`
(already in the tree). Cumulative diff is ~200 LOC across
`zero/native/zero-c/src/{emit_macho64.c, emit_elf64.c, checker.c, ir.c}`
and `zero/native/zero-c/include/zero.h`.

**These patches are not yet committed to this repo.** They live in the
local vendored compiler tree. A reproducible bootstrap path (either a
`patches/zero-macho-direct-backend.patch` diff or a `scripts/bootstrap.sh`
that clones + patches + builds upstream) is **future work**. Anyone
cloning AgentGuard today will hit `CGEN004: direct AArch64 Mach-O value
kind is unsupported` when building with the stock `~/.zero/bin/zero`.

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
| `host-adapter` | 94 | Full Cursor adapter incl. chained commands, model-family routing, real-payload shapes, SEC inventory |
| `ledger-append` | 6 | Real append behavior across separate process invocations |
| `session` | 13 | session start/current/end + host-flag handling |
| `hooks-install` | 16 | install/uninstall + 7-event fragment + claude/codex deferred error |
| `lease-evidence` | 15 | Evidence-backed lease (bypass + edits + check-state gates) |
| `pack-state` | 10 | State-aware pack across 6 observable states |

Total: 15 suites, ~210 assertions, 0 failed in ~55s.

---

## Honest gaps still open

1. **Claude and Codex adapters not safe to enable.** Plugin configs exist
   but the binary doesn't dispatch their envelope shapes. Documented
   `scaffolded`. Don't enable in those hosts until the multi-host envelope
   dispatch lands.
2. **Real `verify` diff** still pipe-pattern (host-tracked via
   afterFileEdit hook), not git-aware. If files are edited outside the
   agent's hooks (manual edit in another editor, generated files,
   `git stash`), AgentGuard doesn't see them.
3. **Lease `issuedAt` and `expiresAt`** are sentinel strings until
   `std.time` lands. Lease expiry is presence-only.
4. **Lease `diffHash`** is the literal `"none-since-reset"`. Real content
   hashing waits on `std.fs.readBytes` + a hash primitive.
5. **`pack` recent_ledger** is a pointer, not the actual recent rows.
   Real ledger readback waits on `std.fs.readBytes`.
6. **`scan` `package.json` script parsing** is conventional-not-parsed.
   The `verified:false` field advertises this.
7. **Bootstrap reproducibility** — anyone cloning will hit a build wall.
   Compiler patches need to ship as either a `.patch` file or a
   `scripts/bootstrap.sh` automation.
