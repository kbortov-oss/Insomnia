import Foundation
import Darwin

@main struct ReadyAcknowledgementTests {
    static func rejects(_ body: () throws -> Void) {
        do { try body(); fatalError("Expected a refused acknowledgement path") } catch {}
    }
    static func main() throws {
        precondition(geteuid() != 0, "Run offline checks as a normal user")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("insomnia-ready-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        let session = root.appendingPathComponent("session")
        try fm.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try createReadyAcknowledgement(in: session)
        let ack = session.appendingPathComponent("ready")
        let original = try Data(contentsOf: ack)
        precondition(original == Data("ready".utf8))
        rejects { try createReadyAcknowledgement(in: session) }
        let afterRefusal = try Data(contentsOf: ack)
        precondition(afterRefusal == original, "Existing files must not be overwritten")
        try fm.removeItem(at: ack)
        let target = root.appendingPathComponent("unrelated-file")
        try Data("untouched".utf8).write(to: target)
        try fm.createSymbolicLink(at: ack, withDestinationURL: target)
        rejects { try createReadyAcknowledgement(in: session) }
        let protected = try String(contentsOf: target)
        precondition(protected == "untouched", "A symlink target must not receive privileged writes")
        let link = root.appendingPathComponent("directory-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: session)
        rejects { try createReadyAcknowledgement(in: link) }
        try fm.removeItem(at: ack)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: session.path)
        rejects { try createReadyAcknowledgement(in: session) }
        print("PASS: exclusive acknowledgement, existing-file refusal, final symlink refusal, directory symlink refusal, private-directory requirement")
    }
}
