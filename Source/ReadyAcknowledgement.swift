import Foundation
import Darwin

// The helper runs as root, but this directory belongs to the GUI user. Pin a
// private directory descriptor and create one new file; never follow a final
// symlink or replace an existing pathname with privileged writes.
func createReadyAcknowledgement(in directory: URL) throws {
    func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directoryFD >= 0 else { throw failure() }
    defer { close(directoryFD) }
    var info = stat()
    guard fstat(directoryFD, &info) == 0 else { throw failure() }
    guard info.st_uid != 0, info.st_mode & 0o077 == 0 else { throw POSIXError(.EACCES) }
    let fileFD = openat(directoryFD, "ready", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    guard fileFD >= 0 else { throw failure() }
    defer { close(fileFD) }
    let payload = Array("ready".utf8)
    let count = payload.withUnsafeBytes { bytes in
        Darwin.write(fileFD, bytes.baseAddress!, bytes.count)
    }
    guard count == payload.count else { throw POSIXError(.EIO) }
}
