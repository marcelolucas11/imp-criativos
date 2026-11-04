import Foundation

enum Paths {
    /// ~/Library/Application Support/IMP Criativos
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("IMP Criativos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var clients: URL { ensure(appSupport.appendingPathComponent("clients", isDirectory: true)) }
    static var jobs: URL { ensure(appSupport.appendingPathComponent("jobs", isDirectory: true)) }
    static var updates: URL { ensure(appSupport.appendingPathComponent("updates", isDirectory: true)) }

    static func jobFolder(_ id: UUID) -> URL {
        ensure(jobs.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]

    static func listImages(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { return [] }
        return files
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Deixa um texto seguro para usar em nome de arquivo.
    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        for scalar in folded.unicodeScalars {
            out.unicodeScalars.append(allowed.contains(scalar) ? scalar : "-")
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }
}
