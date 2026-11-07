import Foundation
import Combine

/// Perfis de clientes, um arquivo JSON por cliente em Application Support/clients.
@MainActor
final class ClientStore: ObservableObject {
    @Published private(set) var clients: [ClientProfile] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        load()
        if clients.isEmpty { save(.example) }
        migrateLegacyDefaults()
    }

    /// 1.0.0-beta.14/15 (app só de cassino online e bet): perfis que ainda têm uma lista padrão antiga sem nenhuma
    /// edição (6 eixos até a beta.13 ou os 50 da beta.14) passam a usar os eixos padrão atuais; o texto do perfil
    /// de exemplo antigo é atualizado.
    /// Perfis com eixos personalizados ficam como estão (o botão "Usar os 50 eixos padrão" troca quando quiser).
    func migrateLegacyDefaults() {
        for var profile in clients {
            var changed = false
            if profile.usesOutdatedDefaultAxes {
                profile.axes = ClientProfile.defaultAxes
                changed = true
            }
            if profile.extraInstructions == ClientProfile.legacyExampleInstructions {
                profile.extraInstructions = ClientProfile.exampleInstructions
                changed = true
            }
            if changed {
                save(profile)
                AppLog.info(.clientes, "Cliente \"\(profile.name)\" passou a usar os \(ClientProfile.defaultAxes.count) eixos padrão de cassino e bet.")
            }
        }
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.clients, includingPropertiesForKeys: nil)) ?? []
        clients = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ClientProfile.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ profile: ClientProfile) {
        let url = Paths.clients.appendingPathComponent("\(profile.id.uuidString).json")
        if let data = try? encoder.encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
        if let i = clients.firstIndex(where: { $0.id == profile.id }) {
            clients[i] = profile
        } else {
            clients.append(profile)
        }
        clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ profile: ClientProfile) {
        try? FileManager.default.removeItem(at: Paths.clients.appendingPathComponent("\(profile.id.uuidString).json"))
        clients.removeAll { $0.id == profile.id }
    }

    func client(_ id: UUID?) -> ClientProfile? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    // MARK: exportar / importar (.impcliente) — para trocar perfis entre sócios

    func export(_ profile: ClientProfile, to url: URL) throws {
        try encoder.encode(profile).write(to: url, options: .atomic)
    }

    @discardableResult
    func importProfile(from url: URL) throws -> ClientProfile {
        var p = try decoder.decode(ClientProfile.self, from: Data(contentsOf: url))
        if clients.contains(where: { $0.id == p.id }) {
            p.id = UUID()
            p.name += " (importado)"
        }
        save(p)
        return p
    }
}
