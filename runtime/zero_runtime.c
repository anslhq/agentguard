/* AgentGuard runtime shim for the Zero v0.1.3 direct backend on hosts where
 * the direct executable path does not yet implement hosted I/O symbols.
 *
 * Provides the C symbols the Zero compiler expects when emitting `--emit obj`
 * on darwin-arm64 / linux. Matches the conformance pattern in
 * zerolang/scripts/test-native.sh:851-857. Keep it tiny — every export here
 * must be a thin wrapper around a libc call. No allocator, no logger.
 */

#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

int zero_world_write(int fd, const char *buf, unsigned len) {
    ssize_t written = write(fd, buf, len);
    return written < 0 || (unsigned long long)written != len;
}

int zero_fs_exists(const char *path, unsigned len, unsigned op) {
    char buf[4096];
    if (len >= sizeof(buf)) return 0;
    memcpy(buf, path, len);
    buf[len] = '\0';
    switch (op) {
    case 0: return access(buf, F_OK) == 0 ? 1 : 0;
    case 1: { struct stat st; return stat(buf, &st) == 0 && (st.st_mode & S_IFDIR) ? 1 : 0; }
    case 2: return mkdir(buf, 0755) == 0 || errno == EEXIST ? 1 : 0;
    case 3: return unlink(buf) == 0 ? 1 : 0;
    case 4: return rmdir(buf) == 0 ? 1 : 0;
    default: return 0;
    }
}

int zero_fs_write_path(const char *path, unsigned path_len, const char *data, unsigned data_len) {
    char buf[4096];
    if (path_len >= sizeof(buf)) return 0;
    memcpy(buf, path, path_len);
    buf[path_len] = '\0';
    int fd = open(buf, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 0;
    ssize_t written = write(fd, data, data_len);
    close(fd);
    return written >= 0 ? (unsigned)written : 0;
}

/* Append semantics: O_APPEND so concurrent writers atomically append
 * (POSIX guarantees atomicity for single write() calls <= PIPE_BUF).
 * AgentGuard ledger rows are always well under that bound.
 *
 * Used by std.fs.appendBytes(path, bytes) on darwin-arm64 via the
 * Mach-O backend patch that introduces IR_VALUE_FS_APPEND_BYTES_PATH.
 * Returns bytes-written, or 0 on failure. */
int zero_fs_append_path(const char *path, unsigned path_len, const char *data, unsigned data_len) {
    char buf[4096];
    if (path_len >= sizeof(buf)) return 0;
    memcpy(buf, path, path_len);
    buf[path_len] = '\0';
    int fd = open(buf, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return 0;
    ssize_t written = write(fd, data, data_len);
    close(fd);
    return written >= 0 ? (unsigned)written : 0;
}

int zero_fs_read_path(const char *path, unsigned path_len, char *buf_ptr, unsigned buf_len) {
    char pbuf[4096];
    if (path_len >= sizeof(pbuf)) return 0;
    memcpy(pbuf, path, path_len);
    pbuf[path_len] = '\0';
    int fd = open(pbuf, O_RDONLY);
    if (fd < 0) return 0;
    /* Drain the descriptor up to buf_len bytes. /dev/stdin returns the full
     * piped buffer in one read on macOS for pipes <= PIPE_BUF, but we still
     * loop on EINTR / partial reads for files. */
    unsigned total = 0;
    while (total < buf_len) {
        ssize_t n = read(fd, buf_ptr + total, buf_len - total);
        if (n < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (n == 0) break;
        total += (unsigned)n;
    }
    close(fd);
    return (int)total;
}
