import AppKit
import SwiftUI

/// Menu do ícone na barra de menus (modo segundo plano).
struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var runner: JobRunner
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    private var active: [Job] { jobs.jobs.filter { $0.state == .running } }
    private var inReview: [Job] { jobs.jobs.filter { $0.state == .review } }

    var body: some View {
        Text("IMP Criativos \(AppInfo.version)")

        Divider()

        if active.isEmpty {
            Text("Nenhum lote em andamento")
        } else {
            ForEach(active) { job in
                Button("\(job.name) — \(job.finishedSteps)/\(job.totalSteps) (\(Int(job.progress * 100))%)") {
                    open(.job(job.id))
                }
            }
        }
        if !inReview.isEmpty {
            Text("\(inReview.count) lote(s) aguardando revisão")
        }

        Divider()

        Button("Abrir IMP Criativos") { open(model.selection ?? .home) }
            .keyboardShortcut("o")
        Button("Novo lote") { open(.newJob) }
        Button("Limpar logo") { open(.cleanOnly) }
        if !active.isEmpty {
            Button("Pausar todos os lotes") { runner.pauseAll() }
        }
        let failures = jobs.jobs.filter { $0.state != .cancelled }.reduce(0) { $0 + $1.failureCount }
        if failures > 0 {
            Button("Tentar falhas de novo em todos os lotes (\(failures))") { runner.retryAllFailed() }
        }
        Button("Histórico…") { open(.logs) }

        Divider()

        if let r = updater.available {
            Button("Instalar versão \(r.version)…") { open(.settings) }
        } else {
            Button("Buscar atualização") {
                let beta = settings.includeBetaUpdates
                Task { await updater.check(includeBeta: beta) }
            }
        }
        Button("Configurações…") { open(.settings) }

        Divider()

        Button("Sair do IMP Criativos") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ item: SidebarItem) {
        model.selection = item
        AppDelegate.mainWindowOpened()
        openWindow(id: "main")
    }
}
