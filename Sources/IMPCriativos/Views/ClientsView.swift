import SwiftUI

struct ClientsView: View {
    @EnvironmentObject var clients: ClientStore
    @State private var selected: UUID?
    @State private var message: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(clients.clients) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                            Text("\(c.removeItems.count) itens · \(c.axes.count) eixos").font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(c.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let p = ClientProfile.newProfile()
                        clients.save(p)
                        selected = p.id
                        AppLog.info(.clientes, "Novo perfil de cliente criado.")
                    } label: { Image(systemName: "plus") }
                    .help("Novo cliente")
                    Button {
                        guard let url = Pickers.openFile(title: "Importar perfil de cliente", extensions: ["impcliente", "json"]) else { return }
                        do {
                            let p = try clients.importProfile(from: url)
                            selected = p.id
                            AppLog.info(.clientes, "Perfil \"\(p.name)\" importado.", details: url.lastPathComponent)
                        } catch {
                            message = "Arquivo inválido: \(error.localizedDescription)"
                            AppLog.error(.clientes, "Falha ao importar perfil: \(error.localizedDescription)", details: url.path)
                        }
                    } label: { Image(systemName: "square.and.arrow.down") }
                    .help("Importar perfil (.impcliente)")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 250)
            .background(Color(white: 0.09))

            Divider()

            if let id = selected, let c = clients.client(id) {
                ClientEditor(original: c, onDeleted: { selected = nil })
                    .id(id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.2").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Selecione ou crie um cliente").foregroundStyle(.secondary)
                    Text("Cada cliente guarda o que remover, os eixos de variação e instruções extras.\nOs perfis ficam só no seu Mac.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = clients.clients.first?.id } }
        .alert("Clientes", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

struct ClientEditor: View {
    let original: ClientProfile
    var onDeleted: () -> Void
    @EnvironmentObject var clients: ClientStore
    @State private var draft: ClientProfile
    @State private var confirmDelete = false
    @State private var savedFlash = false

    init(original: ClientProfile, onDeleted: @escaping () -> Void) {
        self.original = original
        self.onDeleted = onDeleted
        _draft = State(initialValue: original)
    }

    private var dirty: Bool { draft != original }

    private func itemBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < draft.removeItems.count ? draft.removeItems[i] : "" },
                set: { if i < draft.removeItems.count { draft.removeItems[i] = $0 } })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Cliente") {
                    TextField("Nome", text: $draft.name)
                    Stepper(value: $draft.defaultVariations, in: 1...10) {
                        Text("Variações padrão por criativo: **\(draft.defaultVariations)**")
                    }
                }

                Section {
                    ForEach(Array(draft.removeItems.indices), id: \.self) { i in
                        HStack {
                            TextField(text: itemBinding(i), prompt: Text("Item a remover")) { EmptyView() }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                if i < draft.removeItems.count { draft.removeItems.remove(at: i) }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button { draft.removeItems.append("") } label: { Label("Adicionar item", systemImage: "plus") }
                        .buttonStyle(.borderless)
                } header: {
                    Text("O que remover")
                } footer: {
                    Text("Seja específico: \"Nome Jaqueira Prêmios\", \"@jaqueirapremios\", \"logo da coroa dourada no topo\". Quanto mais claro, melhor a limpeza.")
                }

                Section {
                    ForEach($draft.axes) { $axis in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField(text: $axis.name, prompt: Text("Nome do eixo")) { EmptyView() }
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.headline)
                                Button(role: .destructive) {
                                    draft.axes.removeAll { $0.id == axis.id }
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                            }
                            TextField(text: $axis.instruction, prompt: Text("Instrução para a IA"), axis: .vertical) { EmptyView() }
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...5)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Button {
                            draft.axes.append(VariationAxis(name: "Novo eixo", instruction: "Describe how this variation should differ."))
                        } label: { Label("Adicionar eixo", systemImage: "plus") }
                        Spacer()
                        Button("Restaurar eixos padrão") { draft.axes = ClientProfile.defaultAxes }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Eixos de variação")
                } footer: {
                    Text("Cada variação usa um eixo, em ordem (v1 = 1º eixo, v2 = 2º…). Se pedir mais variações que eixos, eles se repetem. Instruções em inglês costumam funcionar melhor, mas português também funciona.")
                }

                Section {
                    TextField(text: $draft.extraInstructions, prompt: Text("Ex.: nunca mudar a cor do carro; manter o selo 'Autorizado'"), axis: .vertical) { EmptyView() }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                } header: {
                    Text("Instruções extras")
                } footer: {
                    Text("Vão junto em todas as etapas deste cliente.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Excluir", systemImage: "trash") }
                Button {
                    guard let url = Pickers.saveFile(title: "Exportar perfil", name: "\(Paths.slug(draft.name)).impcliente") else { return }
                    do {
                        try clients.export(draft, to: url)
                        AppLog.info(.clientes, "Perfil \"\(draft.name)\" exportado.", details: url.path)
                    } catch {
                        AppLog.error(.clientes, "Falha ao exportar perfil: \(error.localizedDescription)", details: url.path)
                    }
                } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
                .help("Gera um arquivo .impcliente para enviar ao seu sócio")
                Spacer()
                if savedFlash { Text("Salvo").foregroundStyle(Brand.success).transition(.opacity) }
                Button("Descartar alterações") { draft = original }.disabled(!dirty)
                Button("Salvar") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty)
            }
            .padding(12)
        }
        .confirmationDialog("Excluir \(draft.name)?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) {
                clients.delete(original)
                AppLog.warning(.clientes, "Perfil \"\(original.name)\" excluído.")
                onDeleted()
            }
        } message: { Text("Lotes já criados não são afetados.") }
    }

    private func save() {
        draft.removeItems = draft.removeItems.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = "Sem nome" }
        clients.save(draft)
        AppLog.info(.clientes, "Perfil \"\(draft.name)\" salvo.",
                    details: "Remover (\(draft.removeItems.count)): \(draft.removeItems.joined(separator: ", "))\nEixos de variação: \(draft.axes.count)")
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { savedFlash = false } }
    }
}
