import SwiftUI

/// 1.0.0-beta.11: botão que abre um menu em duas camadas — plataforma › modelo.
/// Com `allowNone`, oferece "Nenhuma" (usado na reserva).
struct ModelMenu: View {
    let role: ModelRole
    let selection: ModelChoice?
    var allowNone = false
    var noneLabel = "Nenhuma (não trocar)"
    var width: CGFloat = 320
    let onSelect: (ModelChoice?) -> Void

    @ObservedObject private var catalog = ModelCatalog.shared

    private func item(_ p: ProviderKind, _ model: String, label: String) -> some View {
        let choice = ModelChoice(provider: p, model: model)
        return Toggle(label, isOn: Binding(get: { selection == choice }, set: { _ in onSelect(choice) }))
    }

    var body: some View {
        Menu {
            ForEach(ProviderKind.allCases) { p in
                Menu(p.platformLabel + (APIKeyStore.hasKey(p) ? "" : " — sem chave")) {
                    // 1.0.0-beta.12: lista fixa com todos os modelos, agrupada; nada de digitar nome.
                    let options = catalog.options(p, role: role)
                    ForEach(ModelOption.Tier.allCases, id: \.self) { g in
                        let inGroup = options.filter { $0.tier == g }
                        if !inGroup.isEmpty {
                            Section(g.title) {
                                ForEach(inGroup, id: \.id) { o in item(p, o.id, label: o.menuLabel) }
                            }
                        }
                    }
                    let extra = catalog.extraModels(p, role: role,
                                                    current: selection?.provider == p ? selection?.model : nil)
                    if !extra.isEmpty {
                        Section("Novos, vistos pela sua chave") {
                            ForEach(extra, id: \.self) { m in item(p, m, label: m) }
                        }
                    }
                }
            }
            if allowNone {
                Divider()
                Toggle(noneLabel, isOn: Binding(get: { selection == nil }, set: { _ in onSelect(nil) }))
            }
        } label: {
            Text(selection.map { "\($0.provider.label)  ›  \($0.model)" } ?? noneLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: width)
        .help(selection?.label ?? noneLabel)
    }
}

/// Uma etapa nas Configurações: IA principal e reserva.
struct StageAIRow: View {
    let stage: AIStage
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let v = settings.stage(stage)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.label).fontWeight(.semibold)
                Text(stage.help).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("IA principal") {
                ModelMenu(role: stage.role, selection: v.primary) { choice in
                    if let choice { settings.setPrimary(choice, for: stage) }
                }
            }
            LabeledContent("Reserva se der erro") {
                ModelMenu(role: stage.role, selection: v.backup, allowNone: true) { choice in
                    settings.setBackup(choice, for: stage)
                }
            }
            if let b = v.backup, b == v.primary {
                WarningLabel(text: "A reserva é igual à principal. Escolha outro modelo ou outra plataforma para ela.")
            } else if let b = v.backup, !APIKeyStore.hasKey(b.provider) {
                WarningLabel(text: "Sem a chave do \(b.provider.label), a reserva não será usada.")
            } else if !APIKeyStore.hasKey(v.primary.provider) {
                WarningLabel(text: "Falta a chave do \(v.primary.provider.label) em Chaves de API.")
            }
        }
        .padding(.vertical, 4)
    }
}
