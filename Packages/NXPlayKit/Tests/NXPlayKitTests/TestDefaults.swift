import Foundation

/// A throwaway settings domain, named by a path in the temporary folder: a suite named by a path keeps its plist there,
/// so tests leave nothing in ~/Library/Preferences. (Deleting a ~/Library/Preferences/<suite>.plist after a test
/// didn't hold: cfprefsd wrote the emptied domain back about a minute later.)
func testDefaultsName() -> String {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "nxplay-tests", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "defaults-\(UUID().uuidString)").path
}

/// Empties the domain and deletes its file.
func removeTestDefaults(_ suite: String) {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(atPath: suite + ".plist")
}
