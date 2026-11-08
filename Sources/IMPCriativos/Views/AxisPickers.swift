import SwiftUI

// 1.0.0-beta.18: janelas para escolher os eixos de variação de um cliente.
// - Catálogo do app: os 50 eixos que vêm com o programa, com família, o que muda e risco de texto.
// - Meus eixos: biblioteca de eixos criados pelo usuário (vale para todos os clientes).
// Marcar a bolinha coloca o eixo na lista do cliente; desmarcar tira. Só grava ao Salvar o perfil.

/// Bolinha de seleção: vazia = fora da lista; marcada = na lista.
struct SelectDot: View {
    let on: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? Brand.red : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(on ? "Na lista do cliente — clique para tirar" : "Fora da lista — clique para colocar")
    }
}

/// Etiqueta colorida do risco de o texto sair errado.
struct RiskBadge: View {
    let risk: String

    private var color: Color {
        switch risk {
        case "Alto": return Brand.red
        case "Médio": return Brand.warning
        default: return Brand.success
        }
    }

    var body: some View {
        Text(risk)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

/// Prompt completo de um eixo, mostrado ao clicar em "Ver mais".
private struct PromptBox: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surfaceRaised))
    }
}

// MARK: - Catálogo do app

struct AxisCatalogSheet: View {
    @Binding var axes: [VariationAxis]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var family = "Todas"
    @State private var risk = "Todos"
    @State private var expanded: Set<Int> = []

    private var filtered: [BuiltInAxis] {
        let q = search.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return AxisCatalog.builtIn.filter { e in
            (family == "Todas" || e.family == family)
            && (risk == "Todos" || e.textRisk == risk)
            && (q.isEmpty || "\(e.name) \(e.change) \(e.family) \(e.instruction)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q))
        }
    }

    private func isOn(_ e: BuiltInAxis) -> Bool { axes.contains { $0.instruction == e.instruction } }

    private func set(_ e: BuiltInAxis, _ on: Bool) {
        if on {
            if !isOn(e) { axes.append(e.axis) }
        } else {
            axes.removeAll { $0.instruction == e.instruction }
        }
    }

    private var selectedCount: Int { AxisCatalog.builtIn.filter(isOn).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Catálogo de eixos do app").font(.title2.bold())
                    Text("Marque a bolinha para colocar o eixo na lista do cliente; desmarque para tirar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selectedCount) de \(AxisCatalog.builtIn.count) na lista")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 18)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField(text: $search, prompt: Text("Buscar por nome, família ou o que muda")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Picker("Família", selection: $family) {
                    Text("Todas").tag("Todas")
                    ForEach(AxisCatalog.families, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 260)
                Picker("Risco de texto", selection: $risk) {
                    Text("Todos").tag("Todos")
                    ForEach(AxisCatalog.risks, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 190)
                Spacer()
                Button("Marcar visíveis") { filtered.forEach { set($0, true) } }
                Button("Desmarcar visíveis") { filtered.forEach { set($0, false) } }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            CatalogHeaderRow()
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { e in
                        catalogRow(e)
                        Divider()
                    }
                    if filtered.isEmpty {
                        Text("Nenhum eixo com esse filtro.")
                            .foregroundStyle(.secondary)
                            .padding(30)
                    }
                }
            }

            Divider()
            HStack {
                Text("As mudanças entram na lista do cliente. Clique em Salvar no perfil para gravar.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 560, idealHeight: 700)
    }

    @ViewBuilder
    private func catalogRow(_ e: BuiltInAxis) -> some View {
        let on = isOn(e)
        let open = expanded.contains(e.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SelectDot(on: on) { withAnimation(.easeInOut(duration: 0.12)) { set(e, !on) } }
                    .frame(width: 26)
                Text(verbatim: "\(e.number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
                Text(e.name)
                    .font(.headline)
                    .frame(width: 200, alignment: .leading)
                Text(e.family)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 190, alignment: .leading)
                Text(e.change)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RiskBadge(risk: e.textRisk)
                    .frame(width: 70)
                Button(open ? "Ver menos" : "Ver mais") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if open { expanded.remove(e.id) } else { expanded.insert(e.id) }
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 80)
            }
            if open {
                PromptBox(text: e.instruction)
                    .padding(.leading, 72)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(on ? Brand.red.opacity(0.06) : Color.clear)
    }
}

private struct CatalogHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Usar").frame(width: 26)
            Text("Nº").frame(width: 26, alignment: .trailing)
            Text("Nome").frame(width: 200, alignment: .leading)
            Text("Família").frame(width: 190, alignment: .leading)
            Text("O que muda").frame(maxWidth: .infinity, alignment: .leading)
            Text("Risco de texto").frame(width: 70)
            Text("Prompt").frame(width: 80)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }
}

// MARK: - Meus eixos (personalizados)

struct CustomAxesSheet: View {
    @Binding var axes: [VariationAxis]
    @EnvironmentObject var library: CustomAxisStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var expanded: Set<UUID> = []
    @State private var toDelete: CustomAxis?

    private var filtered: [CustomAxis] {
        let q = search.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return library.axes.filter { c in
            q.isEmpty || "\(c.name) \(c.note) \(c.instruction)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
        }
    }

    private func isOn(_ c: CustomAxis) -> Bool {
        axes.contains { $0.id == c.id || $0.instruction == c.instruction }
    }

    private func set(_ c: CustomAxis, _ on: Bool) {
        if on {
            if !isOn(c) { axes.append(c.axis) }
        } else {
            axes.removeAll { $0.id == c.id || $0.instruction == c.instruction }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meus eixos").font(.title2.bold())
                    Text("Eixos criados por você, para usar em qualquer cliente. Marque a bolinha para colocar na lista do cliente.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(library.axes.filter(isOn).count) de \(library.axes.count) na lista")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 18)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField(text: $search, prompt: Text("Buscar nos meus eixos")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Spacer()
                Button {
                    let new = library.add()
                    search = ""
                    expanded.insert(new.id)
                } label: { Label("Novo eixo", systemImage: "plus") }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Text("Usar").frame(width: 26)
                Text("Nome").frame(width: 220, alignment: .leading)
                Text("O que muda").frame(maxWidth: .infinity, alignment: .leading)
                Text("Prompt").frame(width: 90)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { c in
                        customRow(c)
                        Divider()
                    }
                    if library.axes.isEmpty {
                        VStack(spacing: 6) {
                            Text("Você ainda não tem eixos personalizados.").font(.headline)
                            Text("Clique em Novo eixo, ou escreva um eixo na lista de um cliente e salve: ele aparece aqui.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(40)
                    } else if filtered.isEmpty {
                        Text("Nenhum eixo com essa busca.").foregroundStyle(.secondary).padding(30)
                    }
                }
            }

            Divider()
            HStack {
                Text("Editar aqui muda o eixo na biblioteca e na lista deste cliente. Clique em Salvar no perfil para gravar o cliente.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 520, idealHeight: 660)
        .confirmationDialog("Apagar \"\(toDelete?.name ?? "")\" de Meus eixos?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Apagar da biblioteca", role: .destructive) {
                if let c = toDelete { library.delete(c) }
                toDelete = nil
            }
        } message: {
            Text("Clientes que já usam este eixo continuam com ele na lista; desmarque a bolinha para tirar deste cliente.")
        }
    }

    @ViewBuilder
    private func customRow(_ c: CustomAxis) -> some View {
        let on = isOn(c)
        let open = expanded.contains(c.id)
        let empty = c.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SelectDot(on: on, disabled: empty && !on) {
                    withAnimation(.easeInOut(duration: 0.12)) { set(c, !on) }
                }
                .frame(width: 26)
                Text(c.name).font(.headline).frame(width: 220, alignment: .leading)
                Text(c.note.isEmpty ? "—" : c.note)
                    .font(.callout)
                    .foregroundStyle(c.note.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(open ? "Ver menos" : "Ver mais") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if open { expanded.remove(c.id) } else { expanded.insert(c.id) }
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 90)
            }
            if open {
                CustomAxisEditor(axis: c) { edited in
                    library.update(edited)
                    for i in axes.indices where axes[i].id == edited.id {
                        axes[i].name = edited.name
                        axes[i].instruction = edited.instruction
                    }
                } onDelete: {
                    toDelete = c
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(on ? Brand.red.opacity(0.06) : Color.clear)
    }
}

/// Edição de um eixo da biblioteca (aparece ao clicar em "Ver mais").
private struct CustomAxisEditor: View {
    let axis: CustomAxis
    let onSave: (CustomAxis) -> Void
    let onDelete: () -> Void
    @State private var draft: CustomAxis

    init(axis: CustomAxis, onSave: @escaping (CustomAxis) -> Void, onDelete: @escaping () -> Void) {
        self.axis = axis
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: axis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField(text: $draft.name, prompt: Text("Nome do eixo")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                TextField(text: $draft.note, prompt: Text("O que muda (opcional, em poucas palavras)")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
            }
            TextField(text: $draft.instruction, prompt: Text("Prompt do eixo para a IA (em inglês costuma funcionar melhor). Ex.: Complete redesign …"), axis: .vertical) { EmptyView() }
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...10)
                .font(.callout)
            HStack {
                Button(role: .destructive, action: onDelete) { Label("Apagar da biblioteca", systemImage: "trash") }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Desfazer") { draft = axis }.disabled(draft == axis)
                Button("Salvar eixo") {
                    var d = draft
                    d.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    d.note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    d.instruction = d.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                    if d.name.isEmpty { d.name = "Sem nome" }
                    onSave(d)
                }
                .disabled(draft == axis)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surfaceRaised))
        .onChange(of: axis) { _, new in draft = new }
    }
}
