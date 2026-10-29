import Foundation

/// What nxnative says about a game it has a profile for (dm/games/<title ID>/). nxnative keeps no status field, so this
/// reads what its files do say: the profile's header comment marks a game still in bring-up ("In bring-up: on the Mac
/// it reaches World 1-1"), the README's gallery (docs/images/gallery.tsv) lists the games tested on Mac or iPhone with a
/// remark ("60 fps with 1.4.3"), a validated.tsv is the regression harness's last green run and a smoke.tsv its route,
/// and the profile's README opens with what works.
public struct GameProfile: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// In the README's gallery of games tested on Mac or iPhone.
        case tested
        /// Its profile says it's still being brought up, whether or not it's in the gallery.
        case bringUp
        /// A profile, in neither.
        case profiled
    }

    public let titleID: String
    public let name: String
    /// nil when not in bring-up; the profile's remark after "In bring-up:", or empty.
    public let bringUp: String?
    /// nil when not in the gallery; its remark ("60 fps with 1.4.3"), or empty.
    public let galleryNote: String?
    /// The regression harness's last green run: "2026-10-28 · Mac16,7 · macOS 27.2".
    public let validated: String?
    /// The harness has a route for it (smoke.tsv).
    public let hasSmokeRoute: Bool
    /// The README's opening paragraphs, before its first section.
    public let summary: String
    /// The README on the web, when nxnative's remote is GitHub.
    public let notesURL: URL?

    public var stage: Stage { bringUp != nil ? .bringUp : galleryNote != nil ? .tested : .profiled }

    /// "Tested on Mac or iPhone · 60 fps with 1.4.3", "In bring-up: on the Mac it plays to the first battle".
    public var headline: String {
        switch stage {
        case .bringUp:
            return "In bring-up" + (bringUp.map { $0.isEmpty ? "" : ": \($0)" } ?? "")
        case .tested:
            return "Tested on Mac or iPhone"
                + (galleryNote.map { $0.isEmpty ? "" : " · \($0)" } ?? "")
        case .profiled:
            return "nxnative has a profile for it, but doesn't list it as tested yet"
        }
    }

    /// The profiles of these title IDs in an nxnative checkout.
    static func read(repo: URL, titleIDs: Set<String>) -> [String: GameProfile] {
        let games = repo.appending(path: "dm/games", directoryHint: .isDirectory)
        let gallery = Self.gallery(repo.appending(path: "docs/images/gallery.tsv"))
        let web = Self.webRoot(repo)
        var out: [String: GameProfile] = [:]
        for id in titleIDs {
            let folder = games.appending(path: id, directoryHint: .isDirectory)
            guard
                let tsv = try? String(
                    contentsOf: folder.appending(path: "game.tsv"), encoding: .utf8)
            else { continue }
            out[id] = GameProfile(
                titleID: id, gameTSV: tsv, galleryNote: gallery[id],
                validated: try? String(
                    contentsOf: folder.appending(path: "validated.tsv"), encoding: .utf8),
                hasSmokeRoute: FileManager.default.fileExists(
                    atPath: folder.appending(path: "smoke.tsv").path),
                readme: (try? String(
                    contentsOf: folder.appending(path: "README.md"), encoding: .utf8))
                    ?? "",
                notesURL: web?.appending(path: "dm/games/\(id)/README.md"))
        }
        return out
    }

    init(
        titleID: String, gameTSV: String, galleryNote: String?, validated: String?,
        hasSmokeRoute: Bool,
        readme: String, notesURL: URL?
    ) {
        self.titleID = titleID
        let lines = gameTSV.components(separatedBy: .newlines)
        name =
            lines.lazy.compactMap { line -> String? in
                let cells = line.components(separatedBy: "\t")
                return cells.count > 1 && cells[0] == "name" ? cells[1] : nil
            }.first ?? titleID
        // the header comment, before the first row
        let header = lines.prefix {
            $0.hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        bringUp = header.lazy.compactMap(Self.bringUp).first
        self.galleryNote = galleryNote
        self.validated = validated.flatMap(Self.validatedRun)
        self.hasSmokeRoute = hasSmokeRoute
        summary = Self.resolvingLinks(Self.summary(readme), against: notesURL)
        self.notesURL = notesURL
    }

    /// The README's relative links ("[record](validated.tsv)", "(../../../docs/x.md#y)") made absolute against its
    /// own web address; without one, just their text.
    static func resolvingLinks(_ markdown: String, against readme: URL?) -> String {
        markdown.replacing(/\[([^\]]*)\]\(([^)\s]+)\)/) { match in
            let target = String(match.2)
            if target.contains("://") { return String(match.0) }
            guard let readme, let url = URL(string: target, relativeTo: readme)?.absoluteURL else {
                return String(match.1)
            }
            return "[\(match.1)](\(url.absoluteString))"
        }
    }

    /// "In bring-up" in a header line, with its remark; "Bring-up has just started" too.
    static func bringUp(_ line: String) -> String? {
        guard
            let match = line.firstMatch(
                of: /(?i)\b(?:in bring-up|bring-up has just started)\b(?::\s*(.+))?/)
        else { return nil }
        let remark = match.1.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return remark.hasSuffix(".") ? String(remark.dropLast()) : remark
    }

    /// The last row of validated.tsv: "date=… machine=… macos=…" → "2026-10-28 · Mac16,7 · macOS 27.2".
    static func validatedRun(_ text: String) -> String? {
        guard
            let row = text.components(separatedBy: .newlines).last(where: {
                !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty
            })
        else { return nil }
        var fields: [String: String] = [:]
        for word in row.split(whereSeparator: { $0 == "\t" || $0 == " " }) {
            let pair = word.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        let parts = [fields["date"], fields["machine"], fields["macos"].map { "macOS \($0)" }]
            .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The README's paragraphs before its first "## " section, without its "# " title.
    static func summary(_ readme: String) -> String {
        readme.components(separatedBy: .newlines)
            .prefix { !$0.hasPrefix("## ") }
            .filter { !$0.hasPrefix("# ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// gallery.tsv: image, name, note, title ID; title ID → note.
    static func gallery(_ file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) where !line.hasPrefix("#") {
            let cells = line.components(separatedBy: "\t").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard cells.count >= 4, cells[3].count == 16 else { continue }
            out[cells[3].uppercased()] = cells[2]
        }
        return out
    }

    /// https://github.com/<owner>/<repo>/blob/HEAD/ for a GitHub origin (https or ssh), from .git/config.
    static func webRoot(_ repo: URL) -> URL? {
        guard
            let config = try? String(
                contentsOf: repo.appending(path: ".git/config"), encoding: .utf8),
            let origin = config.firstMatch(
                of: /\[remote "origin"\][^\[]*?url\s*=\s*(\S+)/.dotMatchesNewlines())
        else { return nil }
        let url = String(origin.1)
        guard
            let path = url.firstMatch(of: /github\.com[:\/]([^\/]+)\/([^\/]+?)(?:\.git)?\/?$/)
        else { return nil }
        return URL(string: "https://github.com/\(path.1)/\(path.2)/blob/HEAD/")
    }
}
