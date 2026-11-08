import Foundation
import Testing
@testable import TTYCat

private func emptyFolder() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("ttycat-install-\(UUID().uuidString)/.ttycat")
}

@Test func anInstallIDIsMadeOnceAndKept() throws {
  let folder = emptyFolder()
  let made = try #require(InstallID.readOrMake(in: folder))
  #expect(InstallID.isValid(made))
  #expect(InstallID.readOrMake(in: folder) == made)
  #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["install-id"])  // no temp files left
}

@Test func theDaemonsInstallIDIsUsed() throws {
  let folder = emptyFolder()
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try "0123456789abcdef0123456789abcdef\n".write(to: folder.appendingPathComponent("install-id"), atomically: true, encoding: .utf8)
  #expect(InstallID.readOrMake(in: folder) == "0123456789abcdef0123456789abcdef")
}

@Test func aBrokenInstallIDIsMadeAgain() throws {
  let folder = emptyFolder()
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try "NOT-AN-ID".write(to: folder.appendingPathComponent("install-id"), atomically: true, encoding: .utf8)
  #expect(InstallID.readOrMake(in: folder, make: { "00000000000000000000000000000001" }) == "00000000000000000000000000000001")
}

@Test func whenTheDaemonGetsThereFirstItsInstallIDWins() throws {
  let folder = emptyFolder()
  let theirs = "fedcba9876543210fedcba9876543210"
  let got = InstallID.readOrMake(in: folder, make: {
    // The daemon links its own in while this one is being made.
    try? theirs.write(to: folder.appendingPathComponent("install-id"), atomically: true, encoding: .utf8)
    return "00000000000000000000000000000002"
  })
  #expect(got == theirs)
}

@Test func onlyLowercaseHexIsAnInstallID() {
  #expect(InstallID.isValid("0123456789abcdef0123456789abcdef"))
  #expect(!InstallID.isValid("0123456789ABCDEF0123456789ABCDEF"))
  #expect(!InstallID.isValid("0123456789abcdef"))
  #expect(!InstallID.isValid("0123456789abcdef0123456789abcdeg"))
}
