# Stdin Spike Report (Issue 00)

Date: 2026-05-20
Compiler: Zero v0.1.3 (released `~/.zero/bin/zero` and locally-built `zerolang/bin/zero` — same source, both reproduce these findings).
Host: macOS darwin-arm64.

## Question

Can Zero v0.1.3 read a JSON payload from stdin in pure Zero, or do we need a POSIX shell shim (ADR-0009 outcome B)?

## Findings

1. **`World.in` does not exist.** The `World` capability in v0.1.3 exposes only `.out` and `.err` write surfaces. Probing `world.in.write("test")` fails with `PAR100 expected '}' after block` (the parser treats `in` as a reserved keyword).
2. **No `std.io.stdin()` helper.** `std.io.stdin()` returns `STD002 unknown std helper`. The full `std.*` surface (extracted via `strings ~/.zero/bin/zero | grep '^std\.'`) does not include any stdin-named helper.
3. **`std.fs.read("/dev/stdin", buf)` works at the source level.** The path form `std.fs.read(path: String, buf: MutSpan<u8>) -> usize` accepts `/dev/stdin` as a path. `zero check --json` reports `ok: true`. The handle form `std.fs.read(&mut file, buf)` is incompatible because `std.fs.openOrRaise → owned<File>` triggers the darwin-arm64 `owned<T>` direct-exe gap (CGEN004 on `--emit exe`); see `zerolang/docs/articles/cross-compilation.md` and `zerolang/conformance/agent-surface/fixtures/owned-drop-direct-backend-unsupported.0`.
4. **Runtime on darwin-arm64 requires the conformance-style `cc` link.** The released binary's `--emit exe --target darwin-arm64` rejects programs containing `std.fs.read` with `CGEN004 direct backend does not support target 'darwin-arm64' for --emit exe`. The locally-built `zerolang/bin/zero` accepts `--emit obj --target darwin-arm64` and produces a working `.o`; linking it via `cc program.o zero_runtime.c -o program` (the maintainer pattern in `zerolang/scripts/test-native.sh:837-861`) yields a runnable binary.
5. **Cross-compile to `linux-musl-x64` works direct** with no `cc` shim — same source builds straight via `bin/zero build --emit exe --target linux-musl-x64`.

## Classification

**ADR-0009 outcome A for everything except hosted I/O on darwin-arm64-native runtime**; B for that one slot (a ~6-line C runtime shim, exactly the maintainer-provided `zero_world_write`/`exit` shim, no shell scripts and no TypeScript). All AgentGuard source remains in Zero. The shim ships alongside the build, not alongside the source.

## Implementation guidance for hook adapters

```zero
let mut buf: [N]u8 = [0,0,...]     // single-line literal of length N
let n = std.fs.read("/dev/stdin", buf)
if n > 0 {
    let span: Span<u8> = buf
    let payload = check std.json.parseBytes(arena, span)   // see Issue 13
    // ... process payload ...
}
```

`N` is set per host's documented max payload size. Claude Code's PreToolUse payload is typically < 64 KiB; the result envelope cap (ADR-0012) keeps replies ≤ 64 KiB. We size the input buffer at 65536 bytes and the response writer at 65536 bytes.

## Reference proof

See `tools/spike/stdin_echo.0` — typechecks `ok: true` against the locally-built compiler and reads `/dev/stdin` correctly when linked per the conformance pattern.
