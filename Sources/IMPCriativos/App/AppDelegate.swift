import AppKit
import SwiftUI

/// Ciclo de vida: segundo plano, ícone no Dock, confirmação ao sair.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var skipQuitConfirmation = false

    @MainActor private var model: AppModel { AppModel.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Notifier.requestPermission()
            AppLog.info(.sistema, "IMP Criativos \(AppInfo.version) aberto.",
                        details: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            model.runner.resumeInterrupted()
            if model.settings.checkUpdatesOnLaunch {
                let beta = model.settings.includeBetaUpdates
                Task { await model.updater.check(includeBeta: beta, silent: true) }
            }
        }
    }

    /// Com "Continuar em segundo plano" ligado, fechar a janela não encerra o app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !model.settings.runInBackground }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard !Self.skipQuitConfirmation, model.runner.hasActiveWork else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "Há um lote em andamento"
            alert.informativeText = "Se sair agora, o lote para e é retomado de onde parou na próxima vez que você abrir o IMP Criativos."
            alert.addButton(withTitle: "Sair")
            alert.addButton(withTitle: "Cancelar")
            alert.alertStyle = .warning
            return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
        }
    }

    // MARK: Dock ↔ barra de menus

    /// Janela principal abriu: ícone volta para o Dock (com a bolinha de "aberto").
    @MainActor static func mainWindowOpened() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Janela principal fechou: em segundo plano o app sai do Dock e fica só na barra de menus.
    @MainActor static func mainWindowClosed() {
        guard AppModel.shared.settings.runInBackground else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let hasMainWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
            if !hasMainWindow { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
