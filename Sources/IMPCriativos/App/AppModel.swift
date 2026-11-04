import Foundation
import Combine

enum SidebarItem: Hashable {
    case home
    case newJob
    case job(UUID)
    case clients
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
    lazy var runner = JobRunner(store: jobs, settings: settings)

    @Published var selection: SidebarItem? = .home

    private var bag = Set<AnyCancellable>()

    private init() {
        // repassa mudanças das lojas para quem observa o modelo (barra de menus, Dock)
        jobs.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    var missingKeys: Bool { !KeychainStore.hasKey(.gemini) && !KeychainStore.hasKey(.openai) }
}
