import AppKit

@MainActor
enum PathPicker {
    static func choose(directory: Bool, startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = !directory  // prod.keys usually lives in ~/.switch
        if let path, !path.isEmpty {
            let url = URL(filePath: (path as NSString).expandingTildeInPath)
            panel.directoryURL = directory ? url : url.deletingLastPathComponent()
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
