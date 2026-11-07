import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var updater: Updater

    private var runningCount: Int { jobs.jobs.filter { $0.state == .running }.count }
    private var reviewCount: Int { jobs.jobs.filter { $0.state == .review }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    PageHeader(title: "Início", subtitle: "Limpe criativos e gere variações em lote.")
                    Button {
                        model.selection = .newJob
                    } label: {
                        Label("Novo lote", systemImage: "plus").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if model.missingKeys {
                    Card {
                        HStack {
                            Image(systemName: "key.fill").foregroundStyle(Brand.warning)
                            VStack(alignment: .leading) {
                                Text("Configure suas chaves de API").font(.headline)
                                Text("Sem a chave do Gemini ou da OpenAI os lotes não rodam.").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Abrir Configurações") { model.selection = .settings }
                        }
                    }
                }

                if let r = updater.available {
                    Card {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Brand.red)
                            Text("Nova versão disponível: \(r.version)").font(.headline)
                            Spacer()
                            Button("Ver atualização") { model.selection = .settings }
                        }
                    }
                }

                HStack(spacing: 14) {
                    StatTile(label: "Em processamento", value: "\(runningCount)", symbol: "gearshape.2", tint: Brand.red)
                    StatTile(label: "Aguardando revisão", value: "\(reviewCount)", symbol: "eye", tint: Brand.warning)
                    StatTile(label: "Gasto estimado no mês", value: jobs.monthCost.usd, symbol: "dollarsign.circle")
                }

                Text("Lotes recentes").font(.title3.weight(.semibold)).padding(.top, 6)
                if jobs.jobs.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nenhum lote ainda.").font(.headline)
                            Text("O app é feito para criativos de cassino online e apostas esportivas (bet). Crie um cliente em Clientes (o que remover e como variar) e depois um Novo lote apontando para a pasta dos criativos.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(jobs.jobs.prefix(10)) { job in
                            Button { model.selection = .job(job.id) } label: { RecentJobRow(job: job) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct RecentJobRow: View {
    let job: Job
    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name).font(.headline)
                    Text("\(job.client.name) · \(job.items.count) criativos · \(job.variationsPerItem) variações · \(job.createdAt.short)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if job.state == .running {
                    ProgressView(value: job.progress).frame(width: 120)
                }
                Text(job.costUSD.usd).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                StatePill(state: job.state)
            }
        }
        .contentShape(Rectangle())
    }
}
