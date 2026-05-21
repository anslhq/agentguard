# AGENTS.md — AgentGuard build notes

Source-of-truth notes for agents working on AgentGuard. Anchored to:

- **`/Users/harsha/Developer/agentguard/zerolang/`** — full clone of the Zero
  language repo (`tylerb-public/zero`). Use this as the **highest source of truth**
  for any Zero question. Beats the released binary's `zero skills get ...`
  output when the two disagree.
- `CONTEXT.md` and `docs/adr/` — AgentGuard's own design contract.

## Mandatory workflow per edit

1. **Always check the docs/skills first. Never guess.**
   - Read `~/.zero/bin/zero skills get <name> --full` first for the released-binary
     surface.
   - When the skill is too thin, read `zerolang/docs/articles/`,
     `zerolang/native/zero-c/src/checker.c` (canonical std signature table),
     and `zerolang/conformance/native/pass/*.0` for the working pattern.
   - If still uncertain, `strings ~/.zero/bin/zero | grep '^std\.'` enumerates
     every implemented `std.*` helper in the v0.1.3 binary.
2. **Cite the file and line.** When changing AgentGuard code, cite the Zero
   example/conformance fixture you copied the pattern from.
3. **The `.cursor/hooks/zero-diagnostics.sh` hook auto-runs `zero check`** on
   every `Write`/`Edit`/`MultiEdit`/`Read` against a `.0` file. Do not rerun
   `zero check` manually after an edit — the hook already did.

## Zero compiler — the two binaries

| Path | What it is | When to use |
|---|---|---|
| `~/.zero/bin/zero` | The **released** v0.1.3 binary (installed via the user's installer). Backed by the same C compiler in `zerolang/native/zero-c/`. | Day-to-day `zero check --json` calls, the diagnostic-hook script, and any pure-checking flow. |
| `/Users/harsha/Developer/agentguard/zerolang/bin/zero` | A **shim** that execs `zerolang/.zero/bin/zero` — the locally-built compiler from this checkout. Same C source, built via `make -C native/zero-c`. | Building & running examples and conformance tests from inside the `zerolang/` checkout. |

Both report `zero 0.1.3`. The local build was confirmed working at
`zerolang/.zero/bin/zero` (700 KiB) after `make -C native/zero-c` succeeded.

## Zero v0.1.3 capability matrix (host: macOS darwin-arm64)

These are the empirical results from probing the v0.1.3 binary on this host.
Update this section whenever you discover a new gap or a new working pattern.

### What works end-to-end (check + build + run on darwin-arm64)

| Capability | Form | Reference |
|---|---|---|
| Single-file `.0` programs (no hosted I/O) | `zero build --emit exe --target darwin-arm64 file.0` | `examples/hello.0`, `examples/direct-exe-return.0` |
| Package mode | `zero build --emit exe --target darwin-arm64 .` (package dir with `zero.json`) | `examples/zero-hash/`, `examples/readall-cli/` (check only on darwin-arm64) |
| `world.out.write` / `world.err.write` | `check world.out.write(span_or_string)` | every example |
| `std.args.get(i) -> Maybe<String>` | `let first = std.args.get(1); if first.has { ... }` | `conformance/native/pass/std-args.0`. **Runtime on darwin-arm64 requires `--emit obj` + `cc` link** (see below). |
| `std.env.get(name) -> Maybe<String>` | same Maybe pattern | `examples/cli-file.0` |
| `std.mem.span(string)` → `Span<u8>` | implicit byte view | `examples/hello.0` |
| `std.mem.eql(a, b)` | structural equality on spans | `examples/cli-file.0` |
| `std.fs.host()` → `Fs` | the capability handle | every `std.fs` example |
| Path-based file write | `std.fs.writeBytes(path, bytes) -> Maybe<usize>` | `examples/cli-file.0` |
| Path-based file read into caller buffer | `std.fs.read(path, mutSpan) -> usize` or `std.fs.readBytes(path, mutSpan) -> Maybe<usize>` | `conformance/native/pass/std-fs.0` |
| Handle-based read (`owned<File>`) | `let mut file = check std.fs.openOrRaise(fs, path); std.fs.read(&mut file, buf)` returns `Maybe<usize>` | `examples/file-copy.0`, `conformance/native/pass/std-fs-resource.0` |
| Allocator-based all-bytes read | `let mut arena = std.mem.arena(storage); std.fs.readAll(arena, fs, path, maxBytes) -> Maybe<owned<ByteBuf>>` | `examples/readall-cli/src/main.0` |
| `owned<ByteBuf>` → span | `std.mem.bufBytes(&buf) -> Span<u8>` and `std.mem.bufLen(&buf) -> usize` | `examples/readall-cli` |
| JSON parsing | `std.json.parse`, `std.json.parseBytes`, `std.json.validate`, `std.json.writeString` | `conformance/native/pass/std-json-*` |
| Hashing | `std.crypto.hash32(span)`, `std.crypto.hmac32(key, span)` | `examples/zero-hash/` |
| CRC | `std.codec.crc32(span)`, `std.codec.crc32Bytes(bytes)` | `examples/codec-varint.0` |

### What does NOT work on darwin-arm64 in v0.1.3 — and the canonical workaround

Any `.0` program that uses **hosted I/O** (`std.fs.*`, `std.args.*`,
`std.env.*`) fails `--emit exe --target darwin-arm64` with diagnostic
**CGEN004**: *"direct backend does not support target 'darwin-arm64' for
--emit exe"*. This is documented in
`zerolang/docs/articles/cross-compilation.md` and proven by
`zerolang/scripts/test-native.sh:837-861`.

**Canonical Zero-maintainer workaround on darwin-arm64** (from
`scripts/test-native.sh`):

```sh
# 1. Cross-compile to a Mach-O object file (no hosted-IO runtime).
bin/zero build --json --emit obj --target darwin-arm64 program.0 --out program.o

# 2. Link with the host `cc` plus a tiny C runtime shim that provides
#    `zero_world_write`, etc. (the maintainers ship a few-line shim).
cat > runtime.c <<'C'
#include <unistd.h>
int zero_world_write(int fd, const char *buf, unsigned len) {
  ssize_t written = write(fd, buf, len);
  return written < 0 || (unsigned long long)written != len;
}
C
cc program.o runtime.c -o program
./program  # works on Darwin arm64
```

For programs **without** hosted I/O (just `world.out.write` on string
literals), `bin/zero build --emit exe --target darwin-arm64 file.0` produces a
runnable Mach-O directly via the `zero-macho64` backend — no `cc`, no shim.
This is what `examples/hello.0`, `examples/direct-exe-return.0`,
`examples/hello-let.0`, and `examples/branch.0` use.

For Linux x86_64 hosts, **everything works with the direct ELF64 backend** — no
`cc` link needed. This is why the Zero maintainers' CI runs in a Vercel Sandbox
Linux container.

### Implication for AgentGuard

ADR-0009 outcome is **B** (Zero compiles, plus a tiny C linker shim per target
where needed) — *not* outcome A (pure Zero everywhere). The shim is shell-free
and ~6 lines of C; it is *not* a "Zero core + TypeScript adapter" split, so
ADR-0009's no-TypeScript-in-runtime invariant holds.

For Issue 00 / Issue 20 scaffolding, the `agentguard` binary's `zero.json`
**must** match the conformance test pattern:

- During development on macOS arm64: build with `--emit exe --target darwin-arm64`
  for hosted-IO-free demos, or `--emit obj --target darwin-arm64 + cc + zero_runtime.c`
  for the real binary that touches `std.fs`/`std.args`.
- For release distribution: cross-compile `--emit exe --target linux-musl-x64`
  (works direct, no shim) and use `--emit obj + cc + zero_runtime.c` on darwin
  targets.

## Stdin reading

Hook adapters need to read JSON from stdin. The canonical Zero v0.1.3 form is:

```zero
let mut buf: [256]u8 = [0, 0, 0, ...]   /* must be a single-line array literal of exact length */
let n = std.fs.read("/dev/stdin", buf)   /* returns usize; 0 on empty */
if n > 0 {
    let span: Span<u8> = buf
    /* parse span as JSON via std.json.parse */
}
```

The path form `std.fs.read(path, buf) -> usize` returns the byte count directly
(no `Maybe`), and does NOT involve `owned<File>` — so it does not trigger the
`owned<T>`-related CGEN004 wall in v0.1.3.

`std.fs.read` typechecks fine. Runtime requires the link-with-`cc` workaround
above on darwin-arm64.

## Package-local module imports

Zero v0.1.3 import semantics (per `zerolang/examples/resource-cli/src/main.0` + `examples/resource-cli/src/config.0`):

- `use config` resolves `src/config.0`.
- `use core.exit_codes` resolves `src/core/exit_codes.0`. Dots denote subdirectory traversal, like `core/exit_codes.0`.
- **All `pub` symbols from the imported module are brought into the importer's scope flat — no namespace prefix.** Reference imported names directly: `EXIT_USAGE`, not `core.exit_codes.EXIT_USAGE`. Attempting the dotted form raises `NAM003 unknown identifier 'core'`.
- `pub const NAME: TYPE = VALUE` exports the constant. `pub const NAME = VALUE` (no type) fails per `conformance/check/fail/public-const-missing-type.0` — always annotate the type.

## Zero v0.1.3 direct-backend MVP subset (CRITICAL)

The direct backends on **both darwin-arm64 (Mach-O) and linux-musl-x64 (ELF64)** ship with a very restricted MVP subset in v0.1.3. The full list of what's REJECTED on these targets (sourced from `zerolang/native/zero-c/src/ir.c:3286-3296` and probed empirically):

- **Top-level `const` declarations.** `pub const X: i32 = 0` fails with "direct backend MVP does not support declarations other than functions". Workaround: wrap in `pub fun x() -> i32 { return 0 }`.
- **Helpers taking non-trivial parameters.** Any helper that takes `String`, `World`, a shape, `Maybe<T>`, or anything other than primitive integers is rejected with "direct backend parameter type is unsupported".
- **Helpers returning non-trivial types.** Same — `String`, shapes, `Maybe<T>`, `owned<T>` returns from non-main functions all fail with "direct backend return type is unsupported".
- **Calls to std functions with runtime-string args.** `std.json.writeString(buf, code)` where `code` is a `Maybe<String>.value` fails with "direct backend calls currently support only same-file function identifiers" — variable strings flowing into std calls hit a byte-view-source restriction.
- **Top-level `choice`, `interface`, type-alias declarations.** Same MVP filter.
- **`raise`-to-exit-code propagation on darwin-arm64.** `Void raises` mains on Mach-O always exit 0 regardless of what raised inside; ELF64 propagates raised errors as exit 1 via the `_start` stub. ADR-0012 exit codes are therefore observable only on linux-musl-x64.

**What IS supported on the direct-backend MVP:**

- `pub fun main(world: World) -> Void raises { ... }` — the magic entry, all hosted I/O happens here.
- `pub fun helper() -> i32 { return 0 }` — zero-arg helpers returning small int / Bool literals.
- `pub fun helper() -> String { return "literal" }` — zero-arg helpers returning string literals (callable from main, but the call-site materialization is restricted — see footgun #5 below).
- `std.args.get`, `std.args.len`, `std.env.get`, `std.mem.eql`, `std.mem.len`, `std.json.writeString` with literal args, `world.out.write`, `world.err.write`, indexed byte loads `span[i]`, `while`, `if`, `return`, integer arithmetic.
- Shapes used as RECORD locals inside main (not as helper return/param types).

**AgentGuard implication:** every CLI module collapses into `src/main.0` until the upstream backends grow ABIs for non-trivial parameters and returns. Modules under `src/cli/`, `src/core/`, `src/lease/`, etc. **still exist for design clarity and for the eventual refactor** but are currently nearly empty / stub-only. Issue 01's diagnostic-codes registry and explain logic live inline in `main` as a giant `if std.mem.eql(...) { return literal envelope }` chain.

**Estimated upstream patch scope to lift the MVP:** 800-1500 LOC across `emit_macho64.c`, `emit_elf64.c`, `emit_elf_aarch64.c`, `emit_coff.c`, and the calling convention layer in `ir.c`. Multi-day contribution. Tracked as future work, not blocking AgentGuard MVP.

## Common syntax footguns I hit on v0.1.3

0. **Constant on the right side of `==` in `if` conditions triggers `PAR100
   expected '}' after block`.** `if A == param { ... }` works; `if param == A
   { ... }` fails when `A` is a top-level `const` or `pub const`. Workaround:
   always put the constant first (`if SEV_INFO == s` not `if s == SEV_INFO`).
   Affects the diagnostic-codes lookup table style of code with many
   `if param == CONST { return ... }` branches. Reproduced in
   `/tmp/twofn2.0`; minimum case is a single function comparing a parameter
   to a top-level const ref.

0a. **In some long functions, nested `if std.mem.eql(maybe.value, "lit")`
    inside another `if std.mem.eql(other_maybe.value, "lit") {` can trigger
    PAR100 even though the same shape compiles standalone.** Workaround:
    flatten the structure by using a single `if std.mem.eql(maybe.value, lit)`
    and inlining the secondary check via `std.fs.exists` only (no second
    Maybe eql). This was hit while implementing the `lease` subcommand;
    standalone repro at `/tmp/probe_double_eql.0` works fine — the failure
    only manifests in the full agentguard main.0 context.

0b. **The local name `code` causes byte-view materialization issues in
    Mach-O direct backend.** A `let code = std.args.get(2)` local works
    structurally but later byte-view operations on it fail with CGEN004
    "direct backend byte views currently support string literals and
    slices". Workaround: rename to `diag_code`, `cmd_code`, etc. Standalone
    repros do not show the issue; only manifested in the full main.0.
    Possibly an IR-level name collision with diagnostic-code emit paths.

0c. **Large stack-allocated `[N]u8` arrays clobber Maybe<String> backing
    storage on Mach-O direct backend.** A `let mut buf: [4096]u8 = [0,
    0, ...]` declared after a `let arg = std.args.get(N)` will overwrite
    the bytes that back `arg.value` once the buffer is touched (e.g. by
    `std.fs.read("/dev/stdin", buf)`). Symptom: `arg.value` length stays
    correct but content becomes garbage (often spaces or NULs), then the
    next byte-view op corrupts further. Workaround: keep stack buffers
    used in conjunction with Maybe<String> values **and** a function
    body bigger than ~2000 lines to ≤1024 bytes. (Earlier we observed
    2048 working when main.0 was smaller; once we added session+hooks
    subcommands and main.0 grew past ~1900 lines, the 2048 buffer
    silently miscompiled — `event_value.value` matched correctly for
    `std.mem.eql` until a build threshold crossed, then started
    returning false on every comparison. Reducing to 1024 fixed it.)
    For payloads larger than 1KB, copy the args.value content out into
    a separate local before declaring the large buffer. Probably a
    stack-frame layout bug in `emit_macho64.c` interacting with
    function-frame size; warrants an upstream report. The safe ceiling
    scales **inversely** with main() size — keep one or the other small.

1. **Multi-line array literals fail to parse** with `PAR100 expected '}' after
   block`. Workaround: put the whole `[N]u8 = [0, 0, 0, ...]` literal on a
   single line. Confirmed against the conformance fixtures, which all use
   single-line literals up to length 128+.
2. **Array literal length is checked strictly**. `let s: [4096]u8 = [0]`
   fails with `TYP002 array literal length does not match expected fixed
   array`. You must spell out exactly N initializers, or use a smaller `[N]u8`.
3. **`world.in` does not exist.** The `World` capability only exposes `.out`
   and `.err`. For stdin, use `std.fs.read("/dev/stdin", buf)` as above.
4. **`std.fs.readAll` takes 4 args**: `(alloc, fs, path, maxBytes)` —
   *not* `(file, buf)`. The handle-based read is `std.fs.read(&mut file, buf)`
   (different function, 2 args, returns `Maybe<usize>`).
5. **`std.fs.read` is overloaded by arg-0 shape**: pass `String` for path-form,
   `mutref<File>` for handle-form. Wrong shape gives `STD003` with
   `expected: String path or mutref<File>`.
6. **Allocator helper is `std.mem.arena(storage)`**, *not* `fixedBufAlloc`.
   The compiler accepts `fixedBufAlloc` as a known std helper (it's in the
   binary's symbol table) but the canonical Zero example pattern uses `arena`.
7. **No reflexive `as i32` casts on strings.** Integer literals coerce against
   context; use suffixes like `42_usize` when ambiguous.

## How to discover Zero's actual std surface

When the skills don't say enough:

```sh
# Every implemented std.* helper in the v0.1.3 binary:
strings ~/.zero/bin/zero | grep -E '^std\.' | grep -v -E 'expects|requires|must|index|argument' | sort -u

# Canonical signature table in the C source:
rg -n 'std\.fs\.|std\.mem\.' /Users/harsha/Developer/agentguard/zerolang/native/zero-c/src/checker.c

# Working example for any std capability:
rg -l 'std\.fs\.read' /Users/harsha/Developer/agentguard/zerolang/examples /Users/harsha/Developer/agentguard/zerolang/conformance/native/pass
```

The local repo has 60+ examples and a `conformance/native/pass/` tree of
self-checked fixtures — when in doubt, copy from there verbatim.

## Cursor hooks layer (already wired)

- [.cursor/hooks.json](.cursor/hooks.json) registers a `postToolUse` hook on
  `Write|Edit|MultiEdit|Read` that runs
  [.cursor/hooks/zero-diagnostics.sh](.cursor/hooks/zero-diagnostics.sh).
- The script auto-runs `zero check --json` against the touched `.0` file (or
  its enclosing `zero.json` package), filters for error/warning diagnostics,
  and injects them as `additional_context` for the next turn.
- Fail-open by design: anything weird and the hook silently returns `{}`.
- The hook is **only for `.0` files**. Non-Zero edits are not touched.

## Cursor envelope — undocumented fields and model-family routing

The Cursor hook payload includes context fields that are not in any
published spec I have read, but that every host envelope carries:

```json
{
  "conversation_id":  "<uuid>",
  "generation_id":    "<uuid>",
  "model":            "claude-opus-4-7" | "gpt-5" | "o3-mini" | "gemini-2-pro" | ...,
  "sandbox":          true | false,
  "session_id":       "<uuid>",
  "hook_event_name":  "beforeShellExecution" | ...,
  "cursor_version":   "3.5.11",
  "workspace_roots":  ["..."],
  "user_email":       "...",
  "transcript_path":  "...",
  ...event-specific fields (command, file_path, last_assistant_message)
}
```

AgentGuard's `hook` subcommand scans the payload once into byte offsets
for `conversation_id`, `generation_id`, `model`, then derives a small
`model_family: i32` from the model prefix:

| model_family | matches |
|--------------|---------|
| `1` (claude) | `claude-*` |
| `2` (gpt)    | `gpt-*`, `o1*`, `o3*`, `o4*` |
| `3` (gemini) | `gemini-*` |
| `0` (unknown / unset) | everything else |

It also tracks `sandboxed: Bool` (true when `"sandbox":true` substring
appears in the payload).

These two signals route the existing CMD002, CMD003, SEC001, and
claim-without-lease responses to model-tuned `agent_message` / `user_message`
/ `followup_message` literals:

- Claude → reflective phrasing ("restate the user's exact ask", "state
  explicitly what gets deleted", etc).
- GPT/o-series → terse, capitalised stop ("BLOCKED:", "REJECTED").
- Gemini → concise stop with delegate-to-user hint.
- Sandboxed → soft warning (for CMD002 only; CMD003 still hard-blocks).
- Unknown / missing model → original generic literal.

This is implemented entirely by byte-comparing `payload[model_start..]`
against literal prefixes — no runtime string allocation, no buffer
slicing, fully within the Mach-O direct-backend MVP.

We deliberately do NOT echo the extracted IDs into stdout JSON yet,
because we cannot safely interpolate runtime byte ranges into the
output stream under the current ABI. Per-conversation logs and dynamic
agent_message bodies that splice the conversation_id are blocked on the
same MVP limitations as `ext-buffer`.

See `tests/run-host-adapter.sh` for the 45 fixture assertions covering
each model family × rule × allowlist combination.

### Rule semantics (post-FP-fix)

**CMD003 (path-escape)** denies `rm -rf <target>` when the target does
*not* resolve into either:

- one of the host's `workspace_roots[]` (exact match or `<root>/<...>`
  sub-path — must be followed by `/` to avoid sibling-name false matches
  like `wsroot=/proj` vs `target=/projectile`), or
- a scratch path: `/tmp/<...>` or `/var/folders/<...>`.

When `workspace_roots[]` is absent (e.g. running outside Cursor), the
old prefix-only behavior applies: `/`, `~`, and `..` targets are denied,
with the `/tmp/` and `/var/folders/` allowlist still in effect.

**SEC001 (.env)** uses basename-based detection. It denies if the
basename starts with `.env` *and* the suffix is not on the allowlist:

- Allowed: `.envrc`, `.env.example`, `.env.sample`, `.env.template`,
  `.env.test`, `.env.tests`, `.env.defaults`, `.env.ci`.
- Denied: `.env`, `.env.local`, `.env.production`, `.env.staging`,
  `.env.development`, `.env.dev`, `.env.prod`, and any other
  `.env.<unknown-suffix>` (conservative default — better to false-
  positive than leak).
- Paths where `.env` appears only inside a directory name
  (`/proj/.env/foo.txt`) or as a substring of a longer basename
  (`agent-environment.ts`) are allowed because the basename doesn't
  start with `.env`.

**stop hook (claim-without-lease)** only enforces when the hook's cwd
contains `.agentguard/`. In any other directory the hook silently
returns `{}`. This keeps the followup_message from leaking into
unrelated Cursor conversations across other projects.

## Plan & issue context

- Plan file: `/Users/harsha/.cursor/plans/agentguard_full_build_acbc64fd.plan.md`
- Issue queue: `.scratch/agentguard/issues/00-26.md`

### Wave 0 status (verified)

- Wave 0.1 (PATH export) — `verified`. `~/.zero/bin/zero` on PATH; `zero --version` returns `0.1.3`.
- Wave 0.2 (Issue 00) — **verified** with one documented downgrade:
  - Workspace scaffold (`src/`, `tests/`, `tooling/`, `plugins/{claude-code,cursor,codex}/`, `runtime/`, `bin/`, `tools/spike/`): laid out.
  - `zero.json` package manifest: `agentguard 0.0.1`, `defaultTarget: "darwin-arm64"`, `devTarget: "host"`.
  - `zero check --json .` clean.
  - `bin/agentguard` builds via `zerolang/bin/zero build --emit exe --target darwin-arm64 .` (16.2 KiB native Mach-O).
  - `agentguard --version` → `agentguard 0.0.1` ✓
  - `agentguard --help` → lists all 14 subcommands ✓
  - `agentguard <unknown>` → prints `agentguard: unknown command: foo` to stderr ✓ — but **exit code is 0, not 64** on darwin-arm64, because the Mach-O backend lacks `raise`-to-exit lowering in v0.1.3. ELF64 (linux-musl-x64 / CI) has full exit-code support via the `_start` stub at `zerolang/native/zero-c/src/emit_elf64.c:3060-3088`. The exit-code contract is verified on linux-musl-x64 in CI; degraded to exit-0 on Mac dev loop. Documented in ADR-0009 amended.
  - Spike reports: `tools/spike/STDIN.md`, `tools/spike/MATCHERS.md`, `tools/spike/stdin_echo.0`, `tools/spike/match_demo.0`.
  - Preflight gate: `tooling/docs-lint/preflight.sh` — exits 0 against current repo state.
  - **Upstream contribution**: `tools/spike/zerolang-macho-byte-view-eq.patch` (4.3 KiB, 70-line diff) implements `IR_VALUE_BYTE_VIEW_EQ` for darwin-arm64 Mach-O. Mirrors the ELF64 algorithm at `emit_elf64.c:1792` in AArch64. Verified by 8/8 fixture-table runtime tests (`/tmp/probe_eql2.0`). PR-ready against `tylerb-public/zero`.

### Upstream patches landed in the local compiler (cumulative)

1. `IR_VALUE_BYTE_VIEW_EQ` — `std.mem.eql` / `std.mem.eqlBytes` / `std.crypto.constantTimeEql` on darwin-arm64 Mach-O. ~55 LOC. Verified 8/8 runtime tests.
2. `IR_VALUE_FS_EXISTS` / `IR_VALUE_FS_IS_DIR` / `IR_VALUE_FS_MAKE_DIR` / `IR_VALUE_FS_REMOVE` / `IR_VALUE_FS_REMOVE_DIR` — routed through `_zero_fs_exists(path, len, op)` C runtime helper. ~30 LOC emitter + ~20 LOC shim.
3. `IR_VALUE_FS_WRITE_PATH` — `std.fs.write(path, data)` routed through `_zero_fs_write_path(path, path_len, data, data_len)` C runtime helper. ~30 LOC emitter + ~15 LOC shim.
4. `IR_VALUE_FS_READ_PATH` — `std.fs.read(path, buf)` via `_zero_fs_read_path`. ~25 LOC emitter + ~20 LOC shim.
5. `IR_VALUE_FS_APPEND_BYTES_PATH` — `std.fs.appendBytes(path, bytes)` via `_zero_fs_append_path` (popen + O_APPEND|O_CREAT). ~40 LOC emitter + ~15 LOC shim.
6. `IR_VALUE_PROC_CAPTURE_SHELL` — `std.proc.captureShell(cmdline, buf)` via `_zero_proc_capture_shell` (popen-based). ~40 LOC emitter + ~25 LOC shim.

All patches are in `zerolang/native/zero-c/src/emit_macho64.c`. The runtime shims are in `runtime/zero_runtime.c`. Combined diff is ~220 LOC across the compiler and ~95 LOC in the runtime.

### Working compiler path (current)

For any AgentGuard `.0` build that uses `std.mem.eql` or `std.fs.*`, **use the locally-built compiler** at `zerolang/bin/zero` because the upstream binary at `~/.zero/bin/zero` is missing the Mach-O patches. Build via `scripts/build.sh` which handles the `--emit obj + cc link` path automatically:

```sh
cd /Users/harsha/Developer/agentguard
zerolang/bin/zero build --emit exe --target darwin-arm64 . --out bin/agentguard
```

The released `~/.zero/bin/zero` remains correct for `zero check --json` (the type-checker is unaffected), which is why the `.cursor/hooks/zero-diagnostics.sh` hook still uses it. Once the patch is upstreamed and a new release ships, both binaries will be equivalent.
