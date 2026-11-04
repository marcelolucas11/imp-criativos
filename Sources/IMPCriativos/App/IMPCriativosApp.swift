import SwiftUI

@main
struct IMPCriativosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("IMP Criativos", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.clients)
                .environmentObject(model.jobs)
                .environmentObject(model.runner)
                .environmentObject(model.updater)
                .environmentObject(model.log)
                .preferredColorScheme(.dark)
                .tint(Brand.red)
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Configurações…") { model.selection = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Novo lote") { model.selection = .newJob }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Buscar atualização…") {
                    model.selection = .settings
                    let beta = model.settings.includeBetaUpdates
                    Task { await model.updater.check(includeBeta: beta) }
                }
            }
        }

        // Ícone na barra de menus — aparece quando "Continuar em segundo plano" está ligado
        MenuBarExtra(isInserted: Binding(get: { model.settings.runInBackground }, set: { _ in })) {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.jobs)
                .environmentObject(model.runner)
                .environmentObject(model.updater)
                .environmentObject(model.settings)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
    }
}
