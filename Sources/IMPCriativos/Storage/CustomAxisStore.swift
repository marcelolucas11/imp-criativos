import Foundation
import Combine

/// Eixo criado pelo usuário, guardado na biblioteca "Meus eixos" (vale para todos os clientes).
/// O `id` é o mesmo do `VariationAxis` que entra na lista do cliente, para saber o que está marcado.
struct CustomAxis: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var instruction: String
    /// "O que muda", em poucas palavras (opcional).
    var note: String = ""
    var createdAt = Date()

    var axis: VariationAxis { VariationAxis(id: id, name: name, instruction: instruction) }
}

/// Biblioteca de eixos personalizados (1.0.0-beta.18), em Application Support/eixos-personalizados.json.
@MainActor
final class CustomAxisStore: ObservableObject {
    @Published private(set) var axes: [CustomAxis] = []

    private struct FileContent: Codable {
        var axes: [CustomAxis]
        /// Eixos apagados da biblioteca: não voltam sozinhos quando um cliente que ainda os usa é salvo.
        var dismissed: [String]
    }

    private var dismissed: Set<String> = []
    private let placeholderInstruction = "Describe how this variation should differ."

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

    init() { load() }

    var fileExists: Bool { FileManager.default.fileExists(atPath: Paths.customAxes.path) }

    func load() {
        guard let data = try? Data(contentsOf: Paths.customAxes),
              let content = try? decoder.decode(FileContent.self, from: data) else { return }
        axes = content.axes
        dismissed = Set(content.dismissed)
    }

    private func persist() {
        let content = FileContent(axes: axes, dismissed: dismissed.sorted())
        if let data = try? encoder.encode(content) {
            try? data.write(to: Paths.customAxes, options: .atomic)
        }
    }

    /// Na primeira vez, traz para a biblioteca os eixos personalizados que já estão nos clientes
    /// (tudo o que não é do catálogo do app nem da lista padrão antiga).
    func seedIfNeeded(from clients: [ClientProfile]) {
        guard !fileExists else { return }
        for profile in clients { absorb(profile.axes, save: false) }
        persist()
        if !axes.isEmpty {
            AppLog.info(.clientes, "\(axes.count) eixos personalizados dos clientes foram para \"Meus eixos\".")
        }
    }

    /// Guarda na biblioteca os eixos personalizados de uma lista (chamado ao salvar um cliente).
    func absorb(_ list: [VariationAxis], save: Bool = true) {
        var changed = false
        for axis in list where isCustom(axis) {
            let name = axis.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let instruction = axis.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty, instruction != placeholderInstruction,
                  !dismissed.contains(key(axis)),
                  !axes.contains(where: { $0.id == axis.id || $0.instruction == instruction }) else { continue }
            axes.append(CustomAxis(id: axis.id, name: name.isEmpty ? "Sem nome" : name, instruction: instruction))
            changed = true
        }
        if changed && save { persist() }
    }

    /// Eixo que não é do catálogo do app.
    func isCustom(_ axis: VariationAxis) -> Bool {
        AxisCatalog.entry(matching: axis) == nil
    }

    @discardableResult
    func add(name: String = "Novo eixo", instruction: String = "", note: String = "") -> CustomAxis {
        let axis = CustomAxis(name: name, instruction: instruction, note: note)
        axes.append(axis)
        persist()
        return axis
    }

    func update(_ axis: CustomAxis) {
        guard let i = axes.firstIndex(where: { $0.id == axis.id }) else { return }
        axes[i] = axis
        persist()
    }

    func delete(_ axis: CustomAxis) {
        axes.removeAll { $0.id == axis.id }
        dismissed.insert(key(axis.axis))
        persist()
    }

    private func key(_ axis: VariationAxis) -> String {
        axis.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
