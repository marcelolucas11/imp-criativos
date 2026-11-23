import SwiftUI
import AppKit

/// 1.0.0-beta.21: aba "Otimizador em Lote (Stories 9:16)".
/// Até 100 imagens → 1080×1920, sem metadados, com variações sutis sorteadas por imagem. Tudo no Mac, sem IA.
struct StoryOptimizerView: View {
    @ObservedObject private var batch = StoryBatch.shared
    @State private var dropTargeted = false
    /// 1.0.0-beta.23: modal "Inspecionar Antes / Depois".
    @State private var showInspector = false

    private var adjustments: StoryAdjustments { batch.options.adjustments }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Otimizador em Lote (Stories 9:16)",
                           subtitle: "Até \(StoryBatch.maxItems) imagens por vez em 1080×1920, sem metadados e com variações sutis. Roda 100% no Mac: sem internet, sem IA e sem custo.")

                filesCard

                HStack(alignment: .top, spacing: 18) {
                    controls
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    previewCard
                        .frame(width: 320)
                }

                runCard

                if let notice = batch.notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .sheet(isPresented: $showInspector) { StoryInspectorView() }
    }

    // MARK: - Imagens

    private var filesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Imagens").font(.headline)
                    Text("\(batch.items.count)/\(StoryBatch.maxItems)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(batch.items.count >= StoryBatch.maxItems ? Brand.warning : .secondary)
                    Spacer()
                    Button {
                        batch.add(Pickers.images(title: "Adicionar imagens"))
                    } label: {
                        Label("Adicionar…", systemImage: "plus")
                    }
                    .disabled(batch.running || batch.items.count >= StoryBatch.maxItems)
                    Button(role: .destructive) {
                        batch.clear()
                    } label: {
                        Label("Limpar tudo", systemImage: "trash")
                    }
                    .disabled(batch.running || batch.items.isEmpty)
                }

                if batch.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30))
                        Text("Arraste até \(StoryBatch.maxItems) imagens (JPG, PNG, WebP) ou uma pasta para cá")
                        Text("ou clique em Adicionar…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .foregroundStyle(dropTargeted ? Brand.red : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(dropTargeted ? Brand.red : Color.white.opacity(0.2))
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86, maximum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(batch.items) { item in
                            StoryTile(item: item, selected: item.id == batch.selectedID, canRemove: !batch.running) {
                                batch.remove(item.id)
                            }
                            .onTapGesture { batch.selectedID = item.id }
                        }
                    }
                    Text("Clique numa imagem para ver o antes e depois. Arraste mais imagens para adicionar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Brand.red, lineWidth: dropTargeted && !batch.items.isEmpty ? 2 : 0)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard !batch.running else { return false }
            batch.add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: - Controles

    private var controls: some View {
        Form {
            Section("Enquadramento 9:16") {
                Picker("Modo", selection: $batch.options.fit) {
                    ForEach(StoryFit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(batch.options.fit.hint).font(.caption).foregroundStyle(.secondary)
                if batch.options.fit == .solid {
                    Picker("Cor de fundo", selection: $batch.options.solidColor) {
                        ForEach(StorySolidColor.allCases) { Text($0.label).tag($0) }
                    }
                    if batch.options.solidColor == .custom {
                        ColorPicker("Cor", selection: colorBinding, supportsOpacity: false)
                    }
                }
            }

            Section("Variações sutis") {
                Picker("Intensidade", selection: $batch.options.intensity) {
                    ForEach(StoryIntensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(batch.options.intensity.hint)
                    .font(.caption)
                    .foregroundStyle(batch.options.intensity == .aggressive ? Brand.warning : .secondary)
                if batch.options.intensity == .custom {
                    customControls
                } else {
                    Text(Self.describe(adjustments, format: batch.options.format))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $batch.options.mirror) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Espelhar horizontalmente")
                        Text("Usar apenas em imagens sem texto.").font(.caption).foregroundStyle(Brand.warning)
                    }
                }
            }

            Section("Texturas, linhas e bordas") {
                Picker("Preset", selection: texturePresetBinding) {
                    ForEach(StoryTexturePreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(batch.options.texturePreset.hint)
                    .font(.caption)
                    .foregroundStyle(batch.options.texturePreset == .intense ? Brand.warning : .secondary)
                if batch.options.texturePreset == .custom {
                    textureControls
                } else if batch.options.texturePreset != .off {
                    Text(Self.describe(batch.options.texture))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if batch.options.texturePreset != .off {
                    Text("Vale junto com a Intensidade acima. Use \"Inspecionar Antes / Depois\" para dar zoom nas letras antes de processar o lote.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Saída") {
                Picker("Formato", selection: $batch.options.format) {
                    ForEach(StoryOutputFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(batch.options.format == .jpg
                     ? "JPEG pela libjpeg-turbo, qualidade sorteada entre 88 e 93, só com perfil sRGB (sem EXIF, XMP, IPTC nem comentários)."
                     : "PNG sem perda (arquivos bem maiores). Sem metadados, só com perfil sRGB.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $batch.options.versionsPerImage, in: StoryOptions.versionsRange) {
                    LabeledContent("Versões por imagem") {
                        Text("\(batch.options.versions)").monospacedDigit()
                    }
                }
                if batch.options.versions > 1 {
                    Text("Cada versão sai com um sorteio diferente (story_001_v1, story_001_v2…). Total: \(batch.items.count * batch.options.versions) arquivos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Nomes", selection: $batch.options.naming) {
                    ForEach(StoryNaming.allCases) { Text($0.label).tag($0) }
                }
                TextField("Prefixo", text: $batch.options.prefix, prompt: Text("story"))
                Text("Exemplo: " + StoryNames.fileName(index: 1, total: max(batch.items.count, 1), prefix: batch.options.prefix,
                                                       code: "a8f3k", naming: batch.options.naming,
                                                       ext: batch.options.format.fileExtension,
                                                       version: batch.options.versions > 1 ? 1 : nil))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batch.outputFolder?.lastPathComponent ?? "Nenhuma pasta escolhida")
                        if let folder = batch.outputFolder {
                            Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Text("Cada lote cria uma pasta stories_data_hora dentro dela.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Escolher pasta…") {
                        if let url = Pickers.folder(title: "Pasta de saída dos stories", start: batch.outputFolder?.path) {
                            batch.outputFolder = url
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .disabled(batch.running)
    }

    @ViewBuilder
    private var customControls: some View {
        Toggle("Micro-recorte e micro-rotação", isOn: $batch.options.custom.geometry)
        if batch.options.custom.geometry {
            slider("Recorte máximo por borda", $batch.options.custom.cropMaxPercent, StoryAdjustments.cropRange, step: 0.1, format: "até %.1f%%")
            slider("Rotação máxima", $batch.options.custom.rotationMaxDegrees, StoryAdjustments.rotationRange, step: 0.05, format: "±%.2f°")
        }
        Toggle("Micro-perspectiva (cantos)", isOn: $batch.options.custom.perspective)
        if batch.options.custom.perspective {
            slider("Deslocamento máximo dos cantos", $batch.options.custom.perspectiveMaxPercent, StoryAdjustments.perspectiveRange, step: 0.1, format: "±%.1f%%")
        }
        Toggle("Brilho, contraste e saturação", isOn: $batch.options.custom.photometric)
        if batch.options.custom.photometric {
            slider("Brilho", $batch.options.custom.brightnessMaxPercent, StoryAdjustments.brightnessRange, step: 0.1, format: "±%.1f%%")
            slider("Contraste", $batch.options.custom.contrastMaxPercent, StoryAdjustments.contrastRange, step: 0.1, format: "±%.1f%%")
            slider("Saturação", $batch.options.custom.saturationMaxPercent, StoryAdjustments.saturationRange, step: 0.1, format: "±%.1f%%")
        }
        Toggle("Temperatura de cor (mais quente / mais fria)", isOn: $batch.options.custom.temperature)
        if batch.options.custom.temperature {
            slider("Temperatura máxima", $batch.options.custom.temperatureMaxKelvin, StoryAdjustments.temperatureRange, step: 25, format: "±%.0fK")
        }
        Toggle("Micro-ruído (anti-banding)", isOn: $batch.options.custom.noise)
        if batch.options.custom.noise {
            slider("Amplitude máxima", $batch.options.custom.noiseMaxAmplitude, StoryAdjustments.noiseRange, step: 0.25, format: "até ±%.2f níveis")
        }
        Toggle("Riscos diagonais pixel a pixel (escurece, clareia, mantém)", isOn: $batch.options.custom.diagonal)
        if batch.options.custom.diagonal {
            slider("Intensidade máxima dos riscos", $batch.options.custom.diagonalMaxAmplitude, StoryAdjustments.diagonalRange, step: 0.5, format: "até ±%.1f níveis")
        }
        Toggle("Deslocamento de canal (R ou B)", isOn: $batch.options.custom.chromaticShift)
        if batch.options.custom.chromaticShift {
            Picker("Deslocamento máximo", selection: $batch.options.custom.chromaticMaxPixels) {
                Text("1px").tag(1)
                Text("até 2px").tag(2)
            }
            .pickerStyle(.segmented)
        }
        Toggle("Granulação de filme (overlay / soft-light)", isOn: $batch.options.custom.filmGrain)
        if batch.options.custom.filmGrain {
            slider("Opacidade máxima", $batch.options.custom.grainMaxOpacityPercent, StoryAdjustments.grainRange, step: 0.25, format: "até %.2f%%")
        }
        Toggle("Vinheta (bordas mais escuras ou mais claras)", isOn: $batch.options.custom.vignette)
        if batch.options.custom.vignette {
            slider("Vinheta máxima nos cantos", $batch.options.custom.vignetteMaxPercent, StoryAdjustments.vignetteRange, step: 0.5, format: "±%.1f%%")
        }
        Toggle("Micro-nitidez ou suavização (sorteado)", isOn: $batch.options.custom.detail)
        Toggle("Variar compressão JPEG (baseline/progressivo, 4:2:0/4:4:4)", isOn: $batch.options.custom.jpegVariation)
            .disabled(batch.options.format != .jpg)
    }

    private var texturePresetBinding: Binding<StoryTexturePreset> {
        Binding(
            get: { batch.options.texturePreset },
            set: { batch.options.selectTexturePreset($0) }
        )
    }

    @ViewBuilder
    private var textureControls: some View {
        Toggle("Linhas diagonais", isOn: $batch.options.customTexture.lines)
        if batch.options.customTexture.lines {
            Picker("Direção", selection: $batch.options.customTexture.lineDirection) {
                ForEach(StoryLineDirection.allCases) { Text($0.label).tag($0) }
            }
            slider("Intensidade / opacidade", $batch.options.customTexture.lineOpacityPercent, StoryTexture.percentRange, step: 1, format: "%.0f%%")
            slider("Espaçamento", $batch.options.customTexture.lineSpacing, StoryTexture.spacingRange, step: 1, format: "%.0f px")
            slider("Espessura", $batch.options.customTexture.lineThickness, StoryTexture.thicknessRange, step: 1, format: "%.0f px")
            Picker("Mistura", selection: $batch.options.customTexture.lineBlend) {
                ForEach(StoryLineBlend.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("A espessura nunca passa do espaçamento menos 1 px. As linhas são sempre escuras; em imagens muito escuras prefira Overlay.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Serrilhado das bordas (quebra o anti-aliasing)", isOn: $batch.options.customTexture.jitter)
        if batch.options.customTexture.jitter {
            slider("Nível de serrilhado", $batch.options.customTexture.jitterPercent, StoryTexture.percentRange, step: 1, format: "%.0f%%")
            Text("Só nas bordas de alto contraste (texto, botões e contornos). O resto da foto não muda.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Aberração cromática RGB (R e B em sentidos opostos)", isOn: $batch.options.customTexture.aberration)
        if batch.options.customTexture.aberration {
            slider("Deslocamento RGB", $batch.options.customTexture.aberrationPercent, StoryTexture.percentRange, step: 1, format: "%.0f%%")
            let px = 1 + Int((Double(StoryTexture.aberrationMaxPixels - 1) * batch.options.customTexture.aberrationPercent / 100).rounded())
            Text("Cerca de \(px) px no nível escolhido (1 a \(StoryTexture.aberrationMaxPixels) px).")
                .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Ofuscação do contraste (bloom + micro-desfoque)", isOn: $batch.options.customTexture.bloom)
        if batch.options.customTexture.bloom {
            slider("Nível de ofuscação", $batch.options.customTexture.bloomPercent, StoryTexture.percentRange, step: 1, format: "%.0f%%")
            Text("Baixo: letras só levemente estilizadas. Alto: perto do limite da leitura.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Resumo das texturas do preset em uma linha.
    static func describe(_ t: StoryTexture) -> String {
        var parts: [String] = []
        if t.lines {
            parts.append("linhas \(t.lineDirection.label.lowercased()), \(Int(t.lineOpacityPercent))%, espaçamento \(Int(t.lineSpacing)) px, espessura \(Int(t.lineThickness)) px, \(t.lineBlend.label)")
        }
        if t.jitter { parts.append("serrilhado \(Int(t.jitterPercent))%") }
        if t.aberration { parts.append("aberração RGB \(Int(t.aberrationPercent))%") }
        if t.bloom { parts.append("ofuscação \(Int(t.bloomPercent))%") }
        return "Sorteado por imagem (70% a 100% do nível): " + (parts.isEmpty ? "nenhum efeito" : parts.joined(separator: " · ")) + "."
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double, format: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step).frame(width: 150)
                Text(String(format: format, value.wrappedValue).replacingOccurrences(of: ".", with: ","))
                    .font(.caption.monospacedDigit())
                    .frame(width: 96, alignment: .trailing)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = batch.options.customColor
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
            },
            set: { newValue in
                guard let ns = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                batch.options.customColor = RGBColor(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
            }
        )
    }

    /// Resumo do preset em uma linha.
    static func describe(_ a: StoryAdjustments, format: StoryOutputFormat) -> String {
        var parts: [String] = []
        if a.geometry {
            parts.append(String(format: "recorte %.1f–%.1f%% e rotação ±%.1f°", a.cropMinPercent, a.cropMaxPercent, a.rotationMaxDegrees))
        }
        if a.perspective { parts.append(String(format: "perspectiva ±%.1f%%", a.perspectiveMaxPercent)) }
        if a.photometric {
            parts.append(String(format: "brilho e contraste ±%.0f%%, saturação ±%.1f%%", a.brightnessMaxPercent, a.saturationMaxPercent))
        }
        if a.temperature { parts.append(String(format: "temperatura ±%.0fK", a.temperatureMaxKelvin)) }
        if a.noise { parts.append(String(format: "ruído ±%.1f–%.1f", a.noiseMinAmplitude, a.noiseMaxAmplitude)) }
        if a.diagonal { parts.append(String(format: "riscos diagonais ±%.0f–%.0f", a.diagonalMinAmplitude, a.diagonalMaxAmplitude)) }
        if a.chromaticShift { parts.append(a.chromaticMaxPixels >= 2 ? "deslocamento de canal até 2px" : "deslocamento de canal 1px") }
        if a.filmGrain { parts.append(String(format: "granulação %.0f–%.0f%%", a.grainMinOpacityPercent, a.grainMaxOpacityPercent)) }
        if a.vignette { parts.append(String(format: "vinheta ±%.0f%%", a.vignetteMaxPercent)) }
        if a.detail { parts.append("nitidez ou suavização") }
        if a.jpegVariation, format == .jpg { parts.append("JPEG baseline/progressivo e 4:2:0/4:4:4") }
        return "Sorteado por imagem: " + parts.joined(separator: " · ").replacingOccurrences(of: ".", with: ",") + "."
    }

    // MARK: - Preview

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Antes / Depois").font(.headline)
                    Spacer()
                    if batch.previewLoading { ProgressView().controlSize(.small) }
                    Button {
                        if let id = batch.selectedID { batch.reroll(id) }
                    } label: {
                        Label("Novo sorteio", systemImage: "dice")
                    }
                    .controlSize(.small)
                    .disabled(batch.selected == nil || batch.running)
                    .help("Sorteia outros valores para esta imagem, dentro dos mesmos limites")
                }
                Button {
                    showInspector = true
                } label: {
                    Label("Inspecionar Antes / Depois", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(batch.selected == nil)
                .help("Abre o antes e depois em tela grande, com cortina, zoom e arrastar")
                if let item = batch.selected {
                    HStack(spacing: 10) {
                        previewPane("Antes", batch.previewBefore)
                        previewPane("Depois · 1080×1920", batch.previewAfter)
                    }
                    Text(item.url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    if batch.options.versions > 1 {
                        Stepper(value: $batch.previewVersion, in: 1...batch.options.versions) {
                            Text("Versão \(batch.previewVersion) de \(batch.options.versions)").font(.caption)
                        }
                        .controlSize(.small)
                        .disabled(batch.running)
                    }
                    if !batch.previewSummary.isEmpty {
                        Text(batch.previewSummary).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if case let .failed(msg) = item.status { ErrorLabel(text: msg) }
                } else {
                    Text("Adicione imagens para ver o antes e depois com as configurações atuais.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
        }
    }

    private func previewPane(_ title: String, _ image: CGImage?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Rectangle().fill(Color.black)
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 136, height: 242)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Brand.stroke))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Processar

    private var runCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle).font(.headline).monospacedDigit()
                        if batch.failedCount > 0 {
                            Text("\(batch.failedCount) com erro — passe o mouse na miniatura para ver o motivo")
                                .font(.caption).foregroundStyle(Brand.red)
                        }
                        if let folder = batch.lastRunFolder, !batch.running, batch.doneCount > 0 {
                            Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if batch.running {
                        Button(role: .cancel) {
                            batch.cancel()
                        } label: {
                            Label(batch.cancelling ? "Cancelando…" : "Cancelar", systemImage: "stop.fill").padding(.horizontal, 6)
                        }
                        .controlSize(.large)
                        .disabled(batch.cancelling)
                    } else {
                        if let folder = batch.lastRunFolder, batch.doneCount > 0 {
                            Button {
                                AppInfo.open(folder)
                            } label: {
                                Label("Abrir pasta", systemImage: "folder")
                            }
                            .controlSize(.large)
                            Button {
                                batch.makeZip()
                            } label: {
                                Label(batch.zipping ? "Compactando…" : "Baixar Tudo (.ZIP)", systemImage: "doc.zipper")
                            }
                            .controlSize(.large)
                            .disabled(batch.zipping)
                        }
                        Button {
                            batch.start()
                        } label: {
                            Label("Processar Lote", systemImage: "play.fill").padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(batch.items.isEmpty || batch.outputFolder == nil)
                    }
                }
                if batch.running || batch.processedOutputs > 0 {
                    ProgressView(value: Double(batch.processedOutputs), total: Double(max(batch.totalOutputs, 1)))
                }
                Text("Processa \(StoryBatch.concurrency) imagens por vez. Dá para trocar de aba enquanto roda.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        let total = batch.items.count
        if batch.running {
            return batch.totalOutputs > total
                ? "\(batch.processedOutputs) de \(batch.totalOutputs) arquivos processados"
                : "\(batch.processedOutputs) de \(total) imagens processadas"
        }
        if batch.finishedCount > 0 {
            return batch.totalOutputs > total
                ? "\(batch.writtenOutputs) de \(batch.totalOutputs) arquivos prontos"
                : "\(batch.doneCount) de \(total) imagens prontas"
        }
        return total == 0 ? "Nenhuma imagem na lista" : "\(total) imagem(ns) prontas para processar"
    }
}

/// Miniatura de uma imagem do lote, com o status e o botão de remover.
struct StoryTile: View {
    let item: StoryBatch.Item
    let selected: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Thumb(url: item.url, maxPixel: 200)
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Brand.red : Brand.stroke, lineWidth: selected ? 2 : 1)
                )
                .overlay(alignment: .bottomLeading) { badge.padding(5) }
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Remover da lista")
            }
        }
        .contentShape(Rectangle())
        .help("\(item.url.lastPathComponent)\n\(item.status.label)\(item.summary.map { "\n\($0)" } ?? "")")
    }

    @ViewBuilder
    private var badge: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .processing:
            ProgressView().controlSize(.mini)
                .padding(3)
                .background(Color.black.opacity(0.6), in: Circle())
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Brand.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Brand.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.gray)
        }
    }
}
