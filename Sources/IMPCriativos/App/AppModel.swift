import Foundation
import Combine

enum SidebarItem: Hashable {
    case home
    case newJob
    case job(UUID)
    case clients
    case logs
    case settings
}

/// Ponto central do app: guarda as lojas de dados, o executor de lotes e o atualizador.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = AppSettings()
    let clients = ClientStore()
    let jobs = JobStore()
    let updater = Updater()
    let log = ActivityLog.shared
    lazy var runner = JobRunner(store: jobs, settings: settings)

    @Published var selection: SidebarItem? = .home
    /// Lote a filtrar quando o Histórico é aberto a partir de um lote.
    @Published var logJobFilter: UUID?

    private var bag = Set<AnyCancellable>()

    private init() {
        // repassa mudanças das lojas para quem observa o modelo (barra de menus, Dock)
        jobs.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    var missingKeys: Bool { !KeychainStore.hasKey(.gemini) && !KeychainStore.hasKey(.openai) }
}
