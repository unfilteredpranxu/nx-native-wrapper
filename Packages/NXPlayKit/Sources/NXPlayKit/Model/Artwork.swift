import Foundation

/// Official key art for Console Mode's backdrop: the eShop banner (1920×1080, on Nintendo's image CDN) that the
/// community title database blawar/titledb lists for each title ID, the source NX2Apple's front end uses too.
/// The list is large (about 90 MB), so it is fetched only while a game has no banner yet, reduced to title ID →
/// banner URL and kept beside the banners for a week; each banner is downloaded once.
actor ArtworkStore {
    static let titleListURL = URL(
        string: "https://raw.githubusercontent.com/blawar/titledb/master/US.en.json")!
    /// The list is third-party data: images only come from Nintendo's CDN, over HTTPS.
    static let imageHost = "img-eshop.cdn.nintendo.net"
    static let indexLifetime: TimeInterval = 7 * 86_400

    nonisolated let directory: URL
    private let titleList: URL
    private let allowsFileURLs: Bool  // tests serve the list and the images from disk
    private var listTried = false  // one download of the list per launch, even when it fails

    init(
        directory: URL = ArtworkStore.defaultDirectory, titleList: URL = ArtworkStore.titleListURL,
        allowsFileURLs: Bool = false
    ) {
        self.directory = directory
        self.titleList = titleList
        self.allowsFileURLs = allowsFileURLs
    }

    /// Caches: everything here can be downloaded again.
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.varyform.nxplay/Banners", directoryHint: .isDirectory)
    }

    /// The banners on disk, by title ID.
    nonisolated func cachedBanners() -> [String: URL] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return Dictionary(
            files.filter { $0.pathExtension == "jpg" }.map {
                ($0.deletingPathExtension().lastPathComponent, $0)
            }, uniquingKeysWith: { a, _ in a })
    }

    /// Downloads the banners of these titles (upper-case title IDs) that aren't on disk, in the order given, handing
    /// each to `each` as it lands → the ones it got.
    func fetch(
        _ titleIDs: [String], each: (@Sendable (String, URL) async -> Void)? = nil
    ) async -> [String: URL] {
        let cached = cachedBanners()
        var seen = Set<String>()
        let wanted = titleIDs.filter { cached[$0] == nil && seen.insert($0).inserted }
        guard !wanted.isEmpty, let links = await index(for: Set(wanted)) else { return [:] }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var got: [String: URL] = [:]
        for id in wanted {
            guard let link = links[id], let url = URL(string: link), allowed(url),
                let data = await download(url)
            else { continue }
            let file = directory.appending(path: "\(id).jpg")
            guard (try? data.write(to: file, options: .atomic)) != nil else { continue }
            got[id] = file
            await each?(id, file)
        }
        return got
    }

    // MARK: - The title list

    struct Index: Codable {
        let fetched: Date
        let banners: [String: String]
    }

    private struct Entry: Decodable {
        let id: String?
        let bannerUrl: String?
    }

    private var indexFile: URL { directory.appending(path: "index.json") }

    /// The title ID → banner URL index: the saved one while it is fresh or knows every wanted title, else the list again.
    private func index(for wanted: Set<String>) async -> [String: String]? {
        let saved = (try? Data(contentsOf: indexFile)).flatMap {
            try? JSONDecoder().decode(Index.self, from: $0)
        }
        if let saved,
            listTried || wanted.isSubset(of: saved.banners.keys)
                || Date.now.timeIntervalSince(saved.fetched) < Self.indexLifetime
        {
            return saved.banners
        }
        guard !listTried else { return nil }
        listTried = true
        guard let data = await download(titleList),
            let banners = await Task.detached(operation: { Self.banners(fromTitleList: data) })
                .value
        else { return saved?.banners }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(Index(fetched: .now, banners: banners)) {
            try? encoded.write(to: indexFile, options: .atomic)
        }
        return banners
    }

    /// titledb's region list: {nsuid: {id, bannerUrl, …}} → {title ID: banner URL}; a title listed twice takes its
    /// lowest nsuid's banner, the same one every time.
    static func banners(fromTitleList data: Data) -> [String: String]? {
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return nil
        }
        var banners: [String: String] = [:]
        for (_, entry) in entries.sorted(by: { $0.key < $1.key }) {
            guard let id = entry.id?.uppercased(), let banner = entry.bannerUrl, !banner.isEmpty,
                banners[id] == nil
            else { continue }
            banners[id] = banner
        }
        return banners
    }

    private func allowed(_ url: URL) -> Bool {
        if allowsFileURLs, url.isFileURL { return true }
        return url.scheme == "https" && url.host == Self.imageHost
    }

    private func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        return data
    }
}
