// The install ID: random, made once for this Mac, and only for rollouts. It says nothing about anyone.
// Whichever asks first makes it, the app when Sparkle checks or the daemon when it asks about a board
// (install_id in daemon/updates.py), so a Mac that has never had a board has one too. It's written
// whole beside the real name and linked into place, which fails if the other got there first: then
// both use the one that's there.
import Foundation

enum InstallID {
  static var folder: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ttycat") }

  static func isValid(_ text: String) -> Bool {
    text.count == 32 && text.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
  }

  /// This Mac's ID, made if there isn't one yet. Nil only if ~/.ttycat can't be written.
  static func readOrMake(in folder: URL = folder, make: () -> String = random) -> String? {
    let file = folder.appendingPathComponent("install-id")
    let files = FileManager.default
    for _ in 0..<3 {
      if let found = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
        if isValid(found) { return found }
        try? files.removeItem(at: file)  // not one of ours: make it again
      }
      do {
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      } catch {
        return nil
      }
      let made = make()
      let temp = folder.appendingPathComponent("install-id.\(getpid()).\(UUID().uuidString.prefix(8))")
      guard (try? made.write(to: temp, atomically: false, encoding: .utf8)) != nil else { return nil }
      defer { try? files.removeItem(at: temp) }
      if link(temp.path, file.path) == 0 { return made }
      if errno != EEXIST { return nil }
    }
    return nil
  }

  /// 128 random bits, as 32 lowercase hex digits. SystemRandomNumberGenerator is the system's secure one.
  static func random() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }
}
