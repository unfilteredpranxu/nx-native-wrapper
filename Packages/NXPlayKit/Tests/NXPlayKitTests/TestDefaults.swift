import Foundation

/// A throwaway settings domain's name; remove it with `removeTestDefaults` when the test is done.
func testDefaultsName() -> String { "nxplay-tests-\(UUID().uuidString)" }

/// Empties the domain and deletes its file: cfprefsd leaves an empty plist in ~/Library/Preferences otherwise, one per
/// test run, for good.
func removeTestDefaults(_ suite: String) {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let plist = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Preferences/\(suite).plist")
    try? FileManager.default.removeItem(at: plist)
}
