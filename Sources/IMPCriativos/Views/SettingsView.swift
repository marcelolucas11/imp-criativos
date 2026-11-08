import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var updater: Updater
    @ObservedObject private var catalog = ModelCatalog.shared

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Configurações")

                Form {
                    Section {
                        APIKeyRow(provider: .gemini, help: "Crie em aistudio.google.com → Get API key")
                        APIKeyRow(provider: .openai, help: "Crie em platform.openai.com → API keys")
                    } header: {
                        Text("Chaves de API")
                    } footer: {
                        Text("As chaves ficam salvas só neste Mac, num arquivo que apenas a sua conta do Mac consegue ler. Nunca vão para o GitHub nem para outro lugar. Cada pessoa usa as próprias chaves.")
                    }

                    Section("Comportamento") {
                        Toggle(isOn: $settings.runInBackground) {
                            VStack(alignment: .leading) {
                                Text("Continuar em segundo plano")
                                Text("Ao fechar a janela, o lote continua e o app fica na barra de menus.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading) {
                                Text("Abrir ao ligar o Mac")
                                Text("Aparece em Ajustes do Sistema → Geral → Itens de Início.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                try LoginItem.set(newValue)
                                loginError = LoginItem.needsApproval ? "Aprove o IMP Criativos em Ajustes do Sistema → Itens de Início." : nil
                            } catch {
                                loginError = error.localizedDescription
                                launchAtLogin = LoginItem.isEnabled
                            }
                        }
                        if let loginError {
                            HStack {
                                WarningLabel(text: loginError)
                                Button("Abrir Itens de Início") { LoginItem.openSystemSettings() }
                            }
                        }
                        Toggle("Avisar por notificação quando um lote terminar", isOn: $settings.notifyOnFinish)
                    }

                    Section("Processamento") {
                        Stepper(value: $settings.maxConcurrent, in: 1...8) {
                            Text("Criativos processados ao mesmo tempo: **\(settings.maxConcurrent)**")
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Pasta padrão de saída")
                                Text(settings.defaultOutputFolder).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button("Alterar…") {
                                if let url = Pickers.folder(title: "Pasta padrão de saída", start: settings.defaultOutputFolder) {
                                    settings.defaultOutputFolder = url.path
                                }
                            }
                        }
                    }

                    SpeedSection()

                    Section {
                        Stepper(value: $settings.retryAttempts, in: 1...10) {
                            VStack(alignment: .leading) {
                                Text("Tentativas em erro temporário: **\(settings.retryAttempts)**")
                                Text("Esperas crescentes: ~2s, 5s, 10s, 20s, 40s… (respeita o tempo pedido pelo servidor).")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $settings.fallbackEnabled) {
                            VStack(alignment: .leading) {
                                Text("Trocar para a reserva automaticamente quando a IA principal falhar")
                                Text("A etapa é refeita com a reserva escolhida em Modelos de IA (erro, sobrecarga, modelo não encontrado…).")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $settings.fallbackOnBlocked) {
                            VStack(alignment: .leading) {
                                Text("Trocar também quando a imagem for bloqueada pelo filtro de conteúdo")
                                Text("Útil quando uma IA recusa o criativo e a reserva aceita.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!settings.fallbackEnabled)
                        if settings.fallbackEnabled && AIStage.allCases.contains(where: { st in
                            settings.stage(st).backup.map { !APIKeyStore.hasKey($0.provider) } ?? false
                        }) {
                            WarningLabel(text: "Alguma reserva é de uma plataforma sem chave salva; nessa etapa não haverá troca.")
                        }
                    } header: {
                        Text("Erros e tentativas")
                    } footer: {
                        Text("Cada tentativa, troca de IA e erro fica registrado em Histórico.")
                    }

                    Section {
                        ForEach(AIStage.allCases) { st in
                            StageAIRow(stage: st)
                                .disabled(st == .planning && !settings.planningEnabled)
                                .opacity(st == .planning && !settings.planningEnabled ? 0.5 : 1)
                        }
                        Toggle("Planejar cada criativo com IA mais forte (recomendado)", isOn: $settings.planningEnabled)
                        Picker("OpenAI — qualidade da imagem", selection: $settings.openaiQuality) {
                            Text("Baixa").tag("low"); Text("Média").tag("medium"); Text("Alta").tag("high")
                        }
                        Picker("Formato do criativo", selection: $settings.defaultFormat) {
                            ForEach(MetaFormat.allCases) { Text($0.label).tag($0) }
                        }
                        HStack(spacing: 10) {
                            Button {
                                Task { await catalog.refresh() }
                            } label: {
                                Label("Atualizar lista de modelos", systemImage: "arrow.clockwise")
                            }
                            .disabled(catalog.refreshing)
                            if catalog.refreshing {
                                ProgressView().controlSize(.small)
                            } else if let d = catalog.lastUpdated {
                                Text("Atualizada \(d.short)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restaurar modelos padrão") { settings.resetModels() }
                        }
                        if let e = catalog.lastError { WarningLabel(text: e) }
                    } header: {
                        Text("Modelos de IA")
                    } footer: {
                        Text("Clique no modelo para escolher a plataforma e a versão de cada etapa, e qual IA assume se ela der erro. A lista já traz todos os modelos de cada plataforma que funcionam no app, mesmo sem chave; lançamentos novos que a sua chave enxergar aparecem no fim (\"Atualizar lista\"). O planejamento também interpreta as instruções do lote.")
                    }

                    Section {
                        LabeledContent("Gemini — por imagem (US$)") {
                            TextField("", value: $settings.priceGeminiImage, format: .number.precision(.fractionLength(3))).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 90)
                        }
                        LabeledContent("OpenAI — por imagem (US$)") {
                            TextField("", value: $settings.priceOpenAIImage, format: .number.precision(.fractionLength(3))).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 90)
                        }
                        LabeledContent("Checagem/análise (US$)") {
                            TextField("", value: $settings.priceAnalysis, format: .number.precision(.fractionLength(4))).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 90)
                        }
                        LabeledContent("Planejamento por criativo (US$)") {
                            TextField("", value: $settings.pricePlanning, format: .number.precision(.fractionLength(3))).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 90)
                        }
                    } header: {
                        Text("Tabela de preços (estimativa)")
                    } footer: {
                        Text("Usada só para estimar o custo antes do lote e somar o gasto. Ajuste conforme o preço atual do seu plano.")
                    }

                    Section {
                        Toggle(isOn: $settings.keepWarningNotices) {
                            VStack(alignment: .leading) {
                                Text("Manter avisos 18+ e de jogo responsável")
                                Text(settings.keepWarningNotices
                                     ? "Ligado: o app mantém o 18+, o \"Jogue com responsabilidade\" e advertências que já estão no criativo."
                                     : "Desligado: o app remove o 18+, o \"Jogue com responsabilidade\" e advertências na limpeza, e as variações não os recriam.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Avisos do criativo")
                    } footer: {
                        Text("Vale para os próximos lotes e para o que for refeito. Vem desligado de fábrica.")
                    }

                    Section("Atualizações") {
                        LabeledContent("Versão instalada") { Text("\(AppInfo.version) (build \(AppInfo.build))").monospacedDigit() }
                        Toggle("Receber versões beta", isOn: $settings.includeBetaUpdates)
                        Toggle("Buscar atualização ao abrir o app", isOn: $settings.checkUpdatesOnLaunch)
                        UpdateRow()
                    }

                    Section("Sobre") {
                        LabeledContent("Feito para") {
                            Text(Niche.summary)
                        }
                        LabeledContent("Repositório") {
                            Link("github.com/\(AppInfo.updateRepo)", destination: URL(string: "https://github.com/\(AppInfo.updateRepo)")!)
                        }
                        LabeledContent("Dados locais") {
                            Button("Abrir pasta") { AppInfo.open(Paths.appSupport) }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .task { await catalog.refreshIfStale() }
    }
}

struct APIKeyRow: View {
    let provider: ProviderKind
    let help: String
    @EnvironmentObject var settings: AppSettings

    @State private var value = ""
    @State private var hasKey = false
    @State private var status: String?
    @State private var ok = false
    @State private var testing = false
    @State private var reveal = false

    private var placeholder: String { hasKey ? "Chave salva — cole outra para trocar" : "Cole a chave aqui" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(provider.label).frame(width: 100, alignment: .leading)
                Group {
                    if reveal {
                        TextField(text: $value, prompt: Text(placeholder)) { EmptyView() }
                    } else {
                        SecureField(text: $value, prompt: Text(placeholder)) { EmptyView() }
                    }
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240, maxWidth: .infinity)
                .onSubmit { if !value.isEmpty { save() } }

                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
                    .help(reveal ? "Ocultar" : "Mostrar o que foi colado")
                Button("Colar") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        value = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .help("Cola a chave copiada")
                Button("Salvar") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    Task { await test() }
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text("Testar") }
                }
                .disabled(!hasKey || testing)
                if hasKey {
                    Button(role: .destructive) {
                        APIKeyStore.delete(provider)
                        AppLog.warning(.configuracoes, "Chave do \(provider.label) removida.")
                        refresh()
                        status = "Chave removida."
                        ok = false
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Remover chave")
                }
            }
            HStack(spacing: 6) {
                if let status {
                    Image(systemName: ok ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(ok ? Brand.success : .secondary)
                    Text(status)
                } else {
                    Text(help)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() { hasKey = APIKeyStore.hasKey(provider) }

    private func save() {
        do {
            try APIKeyStore.save(value, for: provider)
            value = ""
            refresh()
            AppLog.info(.configuracoes, "Chave do \(provider.label) salva.")
            status = "Chave salva neste Mac."
            ok = true
            Task { await ModelCatalog.shared.refresh() }
        } catch {
            status = error.localizedDescription
            ok = false
            AppLog.error(.configuracoes, "Falha ao salvar a chave do \(provider.label): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let p = try ProviderFactory.make(ModelChoice(provider: provider, model: AIStage.analysis.defaultModel(provider)),
                                             config: ProviderConfig(settings))
            try await p.testKey()
            status = "Chave funcionando."
            ok = true
            AppLog.success(.configuracoes, "Teste da chave do \(provider.label): funcionando.")
        } catch {
            status = "Falhou: \(error.localizedDescription)"
            ok = false
            AppLog.error(.configuracoes, "Teste da chave do \(provider.label) falhou: \(error.localizedDescription)",
                         details: [error.aiDetails, "Sugestão: \(error.aiKind.hint)"].compactMap { $0 }.joined(separator: "\n"))
        }
    }
}

struct UpdateRow: View {
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var runner: JobRunner
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    Task { await updater.check(includeBeta: settings.includeBetaUpdates) }
                } label: { Label("Buscar atualização", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(updater.state == .checking || updater.state == .downloading || updater.state == .installing)

                switch updater.state {
                case .idle:
                    if let d = updater.lastChecked { Text("Última verificação: \(d.short)").font(.caption).foregroundStyle(.secondary) }
                case .checking:
                    ProgressView().controlSize(.small); Text("Verificando…").foregroundStyle(.secondary)
                case .upToDate:
                    Label("Você está na versão mais recente.", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.success)
                case .available:
                    EmptyView()
                case .downloading:
                    ProgressView().controlSize(.small); Text("Baixando…").foregroundStyle(.secondary)
                case .installing:
                    ProgressView().controlSize(.small); Text("Instalando… o app vai reiniciar.").foregroundStyle(.secondary)
                case let .failed(msg):
                    ErrorLabel(text: msg)
                }
            }

            if let r = updater.available {
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Versão \(r.version) disponível").font(.headline)
                            if r.prerelease { Text("beta").font(.caption).padding(.horizontal, 6).background(Brand.red.opacity(0.2), in: Capsule()) }
                            Spacer()
                            if let page = r.pageURL { Link("Ver no GitHub", destination: page).font(.caption) }
                        }
                        if !r.notes.isEmpty {
                            ScrollView {
                                Text(r.notes).font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                            .frame(maxHeight: 160)
                        }
                        Button {
                            if runner.hasActiveWork { confirmInstall = true } else { Task { await updater.install(r) } }
                        } label: { Label("Instalar e reiniciar", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .confirmationDialog("Há um lote em andamento", isPresented: $confirmInstall) {
                    Button("Pausar o lote e atualizar") {
                        runner.pauseAll()
                        Task { await updater.install(r) }
                    }
                } message: {
                    Text("O lote é retomado de onde parou depois que o app reiniciar.")
                }
            }
        }
    }
}

/// 1.0.0-beta.19: velocidade original, Modo rápido com segurança e o estado de cada IA.
struct SpeedSection: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var speed = SpeedMonitor.shared

    var body: some View {
        Section {
            Stepper(value: $settings.maxImageRequests, in: 1...6) {
                VStack(alignment: .leading) {
                    Text("Velocidade original: **\(settings.maxImageRequests)** pedidos de imagem ao mesmo tempo por IA")
                    Text("Somando todos os lotes. É para onde o app volta quando algo indica risco.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.fastMode) {
                VStack(alignment: .leading) {
                    Text("Modo rápido com segurança automática")
                    Text("Sobe um pedido por vez enquanto a IA responde bem. Ao primeiro sinal de risco (IA ocupada, limite de uso, tempo esgotado, IA mais lenta, Mac quente ou lote parado) volta na hora para a velocidade original e só tenta subir de novo depois de 10 minutos (30 se repetir).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Stepper(value: $settings.fastImageCeiling, in: max(1, settings.maxImageRequests)...8) {
                VStack(alignment: .leading) {
                    Text("Teto do modo rápido: **\(max(settings.fastImageCeiling, settings.maxImageRequests))** pedidos de imagem ao mesmo tempo por IA")
                    Text("Limite máximo, mesmo com tudo indo bem. Contas novas na OpenAI costumam ter limite baixo por minuto; o app desce sozinho se bater nele.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.fastMode)
            ForEach(ProviderKind.allCases) { p in
                if let snap = speed.snapshots[p] {
                    Label(snap.line, systemImage: snap.inSafeMode ? "shield.lefthalf.filled" : "speedometer")
                        .font(.caption)
                        .foregroundStyle(snap.inSafeMode ? Brand.warning : .secondary)
                }
            }
        } header: {
            Text("Velocidade")
        } footer: {
            Text("A velocidade só muda quantos pedidos vão juntos. Modelo, qualidade, prompts, checagens e refações continuam os mesmos, e cada imagem é conferida (abre no Mac e está no disco) antes de contar como pronta. As variações de um mesmo criativo saem em paralelo até esse limite.")
        }
        .onChange(of: settings.fastMode) { _, _ in settings.applySpeed() }
        .onChange(of: settings.fastImageCeiling) { _, _ in settings.applySpeed() }
        .onChange(of: settings.maxImageRequests) { _, new in
            if settings.fastImageCeiling < new { settings.fastImageCeiling = new }
            settings.applySpeed()
        }
        .task { settings.applySpeed() }
    }
}
