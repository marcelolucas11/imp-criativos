import Foundation
import AppKit
import CryptoKit
import Combine

/// Versão no formato 1.2.3 ou 1.2.3-beta.4
struct SemVer: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int
    let pre: [String]

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1).map(String.init)
        let nums = parts[0].split(separator: ".").compactMap { Int($0) }
        guard nums.count >= 1 else { return nil }
        major = nums[0]
        minor = nums.count > 1 ? nums[1] : 0
        patch = nums.count > 2 ? nums[2] : 0
        pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    var description: String {
        "\(major).\(minor).\(patch)" + (pre.isEmpty ? "" : "-" + pre.joined(separator: "."))
    }

    static func < (a: SemVer, b: SemVer) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        if a.pre.isEmpty != b.pre.isEmpty { return !a.pre.isEmpty } // beta < final
        for (x, y) in zip(a.pre, b.pre) where x != y {
            if let xi = Int(x), let yi = Int(y) { return xi < yi }
            return x < y
        }
        return a.pre.count < b.pre.count
    }
}

struct ReleaseInfo: Equatable {
    let version: String
    let tag: String
    let notes: String
    let zipURL: URL
    let checksumURL: URL?
    let pageURL: URL?
    let prerelease: Bool
}

/// Busca versões novas nas Releases do GitHub, confere integridade e assinatura, e se substitui.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    var available: ReleaseInfo? {
        if case let .available(r) = state { return r }
        return nil
    }

    func check(includeBeta: Bool, silent: Bool = false) async {
        if !silent { state = .checking }
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.updateRepo)/releases?per_page=20")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("IMP-Criativos/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let data = try await HTTP.send(req, attempts: 2)
            guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw AIError("Resposta inesperada do GitHub.")
            }
            let current = SemVer(AppInfo.version) ?? SemVer("0.0.0")!
            var best: (SemVer, ReleaseInfo)?
            for r in list {
                if (r["draft"] as? Bool) == true { continue }
                let pre = (r["prerelease"] as? Bool) ?? false
                if pre && !includeBeta { continue }
                guard let tag = r["tag_name"] as? String, let v = SemVer(tag), v > current else { continue }
                let assets = (r["assets"] as? [[String: Any]]) ?? []
                func asset(_ suffix: String) -> URL? {
                    assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                        .flatMap { $0["browser_download_url"] as? String }
                        .flatMap(URL.init(string:))
                }
                guard let zip = asset(".zip") else { continue }
                let info = ReleaseInfo(version: v.description, tag: tag,
                                       notes: (r["body"] as? String) ?? "",
                                       zipURL: zip, checksumURL: asset(".zip.sha256"),
                                       pageURL: (r["html_url"] as? String).flatMap(URL.init(string:)),
                                       prerelease: pre)
                if best == nil || v > best!.0 { best = (v, info) }
            }
            lastChecked = Date()
            if let best {
                state = .available(best.1)
                if silent {
                    Notifier.post(title: "Atualização disponível",
                                  body: "IMP Criativos \(best.1.version) está pronto para instalar.")
                }
            } else {
                state = silent ? state : .upToDate
            }
        } catch {
            if !silent { state = .failed("Não foi possível buscar atualizações: \(error.localizedDescription)") }
        }
    }

    func install(_ release: ReleaseInfo) async {
        let appURL = Bundle.main.bundleURL
        let appPath = appURL.path
        if appPath.contains("/AppTranslocation/") || appPath.hasPrefix("/Volumes/IMP Criativos") {
            state = .failed("Mova o IMP Criativos para a pasta Aplicativos (ou para o SSD) e abra de lá antes de atualizar.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            state = .failed("Sem permissão para atualizar na pasta \(appURL.deletingLastPathComponent().path).")
            return
        }

        state = .downloading
        do {
            let work = Paths.updates.appendingPathComponent(release.version, isDirectory: true)
            try? FileManager.default.removeItem(at: work)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. baixa o pacote
            let (tmp, response) = try await HTTP.session.download(from: release.zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError("Falha ao baixar a atualização.") }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)

            // 2. confere a integridade (SHA-256 publicado junto na Release)
            if let sumURL = release.checksumURL {
                let sumData = try await HTTP.send(URLRequest(url: sumURL), attempts: 2)
                let expected = String(decoding: sumData, as: UTF8.self)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)?.lowercased() ?? ""
                let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
                guard !expected.isEmpty, expected == actual else {
                    throw AIError("O arquivo baixado não confere com a versão publicada. Atualização cancelada.")
                }
            }

            state = .installing

            // 3. descompacta
            let unzip = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            guard unzip.status == 0 else { throw AIError("Não foi possível descompactar a atualização.") }
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw AIError("Pacote de atualização sem o app.")
            }

            // 4. confere a assinatura de código do app novo
            let verify = try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            guard verify.status == 0 else { throw AIError("Assinatura do app novo inválida. Atualização cancelada.") }
            if let requirement = Self.designatedRequirement(of: appPath), !requirement.contains("cdhash") {
                // app assinado com o certificado da agência: o novo precisa ter a mesma identidade
                let same = try Shell.run("/usr/bin/codesign", ["--verify", "-R=\(requirement)", newApp.path])
                guard same.status == 0 else {
                    throw AIError("O app baixado não foi assinado pela mesma origem. Atualização cancelada.")
                }
            }

            // 5. troca o app quando este processo fechar e reabre
            let script = work.appendingPathComponent("install.sh")
            try """
            #!/bin/sh
            PID="$1"; OLD="$2"; NEW="$3"
            while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
            rm -rf "$OLD.old"
            if mv "$OLD" "$OLD.old" && mv "$NEW" "$OLD"; then
              rm -rf "$OLD.old"
            else
              [ -d "$OLD.old" ] && [ ! -d "$OLD" ] && mv "$OLD.old" "$OLD"
            fi
            xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
            open "$OLD"
            """.write(to: script, atomically: true, encoding: .utf8)

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path, "\(ProcessInfo.processInfo.processIdentifier)", appPath, newApp.path]
            try p.run()

            AppDelegate.skipQuitConfirmation = true
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static func designatedRequirement(of path: String) -> String? {
        guard let r = try? Shell.run("/usr/bin/codesign", ["-d", "-r-", path]) else { return nil }
        let text = r.output + r.error
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("designated => ") }) else { return nil }
        return String(line.dropFirst("designated => ".count))
    }
}

enum Shell {
    struct Result { let status: Int32; let output: String; let error: String }

    static func run(_ tool: String, _ args: [String]) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus,
                      output: String(decoding: o, as: UTF8.self),
                      error: String(decoding: e, as: UTF8.self))
    }
}
