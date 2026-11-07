import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var log: ActivityLog

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    NavigationLink(value: SidebarItem.home) { Label("Início", systemImage: "house") }
                    NavigationLink(value: SidebarItem.newJob) { Label("Novo lote", systemImage: "plus.square.on.square") }
                    NavigationLink(value: SidebarItem.clients) { Label("Clientes", systemImage: "person.2") }
                    NavigationLink(value: SidebarItem.logs) {
                        Label("Histórico", systemImage: "list.bullet.rectangle")
                            .badge(log.unseenErrors > 0 ? Text("\(log.unseenErrors)") : nil)
                    }
                    NavigationLink(value: SidebarItem.settings) {
                        Label("Configurações", systemImage: "gearshape")
                            .badge(updater.available != nil ? Text("1") : nil)
                    }
                }
                Section("Lotes") {
                    if jobs.jobs.isEmpty {
                        Text("Nenhum lote ainda").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(jobs.jobs) { job in
                        NavigationLink(value: SidebarItem.job(job.id)) {
                            JobSidebarRow(job: job)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) { SidebarBrand() }
            .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 320)
        } detail: {
            Group {
                switch model.selection ?? .home {
                case .home: HomeView()
                case .newJob: NewJobView()
                case let .job(id): JobDetailView(jobID: id)
                case .clients: ClientsView()
                case .logs: LogsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.07))
        }
        .frame(minWidth: 1020, minHeight: 680)
        .onAppear { AppDelegate.mainWindowOpened() }
        .onDisappear { AppDelegate.mainWindowClosed() }
    }
}

struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("IMP Criativos").font(.headline)
                Text("\(Niche.name) · v\(AppInfo.version)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct JobSidebarRow: View {
    let job: Job
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.name).lineLimit(1)
            HStack(spacing: 6) {
                if job.state == .running {
                    ProgressView(value: job.progress).progressViewStyle(.linear).frame(width: 60)
                    Text("\(Int(job.progress * 100))%").font(.caption2).monospacedDigit()
                } else {
                    Text(job.state.label).font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
