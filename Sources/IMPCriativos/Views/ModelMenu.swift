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
    @State private var customProvider: ProviderKind = .gemini
    @State private var customName = ""
    @State private var showCustom = false

    var body: some View {
        Menu {
            ForEach(ProviderKind.allCases) { p in
                Menu(p.platformLabel + (APIKeyStore.hasKey(p) ? "" : " — sem chave")) {
                    let current = selection?.provider == p ? [selection?.model ?? ""] : []
                    ForEach(catalog.models(p, role: role, including: current), id: \.self) { m in
                        let choice = ModelChoice(provider: p, model: m)
                        Toggle(m, isOn: Binding(get: { selection == choice }, set: { _ in onSelect(choice) }))
                    }
                    Divider()
                    Button("Digitar outro modelo…") {
                        customProvider = p
                        customName = ""
                        showCustom = true
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
        .alert("Outro modelo — \(customProvider.platformLabel)", isPresented: $showCustom) {
            TextField("nome exato do modelo", text: $customName)
            Button("Usar") {
                let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { onSelect(ModelChoice(provider: customProvider, model: name)) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Use quando a plataforma lançar um modelo que ainda não aparece na lista. O nome precisa ser igual ao da documentação da API.")
        }
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
