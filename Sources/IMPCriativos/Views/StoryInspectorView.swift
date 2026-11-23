import SwiftUI
import AppKit

/// 1.0.0-beta.23: modal de inspeção Antes / Depois do Otimizador em Lote (Stories 9:16).
///
/// Mostra a imagem selecionada com as configurações atuais, em 1080×1920 (os mesmos pixels do arquivo final), para dar zoom
/// direto nas letras e conferir o serrilhado, as linhas e o deslocamento RGB antes de processar o lote.
/// Dois modos (cortina arrastável e lado a lado), zoom Ajustar / 100% / 200% / 400% com pan, e "Re-randomizar".

enum StoryInspectMode: String, CaseIterable, Identifiable {
    case curtain
    case sideBySide

    var id: String { rawValue }
    var label: String { self == .curtain ? "Cortina" : "Lado a lado" }
}

enum StoryInspectZoom: Int, CaseIterable, Identifiable {
    case fit = 0
    case x100 = 100
    case x200 = 200
    case x400 = 400

    var id: Int { rawValue }
    var label: String { self == .fit ? "Ajustar" : "\(rawValue)%" }
}

/// O que aparece do lado "Antes".
enum StoryInspectBefore: String, CaseIterable, Identifiable {
    /// A imagem original só enquadrada em 9:16, sem nenhuma variação.
    case original
    /// Tudo igual ao arquivo final, menos as texturas (mesma geometria: dá para comparar pixel a pixel).
    case plain

    var id: String { rawValue }
    var label: String { self == .original ? "Original enquadrado" : "Sem as texturas" }
    var badge: String { self == .original ? "ANTES · ORIGINAL" : "ANTES · SEM TEXTURAS" }
}

struct StoryInspectorView: View {
    @ObservedObject private var batch = StoryBatch.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode: StoryInspectMode = .curtain
    @State private var zoom: StoryInspectZoom = .fit
    @State private var beforeKind: StoryInspectBefore = .original

    private var beforeImage: CGImage? { beforeKind == .original ? batch.inspectOriginal : batch.inspectPlain }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            ZStack {
                StoryInspectorCanvas(before: beforeImage, after: batch.previewAfter, beforeLabel: beforeKind.badge, mode: mode, zoom: zoom)
                if batch.previewLoading && (beforeImage == nil || batch.previewAfter == nil) {
                    ProgressView().controlSize(.large)
                }
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 760, idealHeight: 900)
        .onAppear { batch.inspecting = true }
        .onDisappear { batch.inspecting = false }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Modo", selection: $mode) {
                ForEach(StoryInspectMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Picker("Zoom", selection: $zoom) {
                ForEach(StoryInspectZoom.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)

            Picker("Antes", selection: $beforeKind) {
                ForEach(StoryInspectBefore.allCases) { Text($0.label).tag($0) }
            }
            .frame(width: 250)
            .help("Original enquadrado: a imagem sem nenhuma variação. Sem as texturas: tudo igual ao arquivo final, menos linhas, serrilhado, aberração e bloom.")

            Spacer(minLength: 8)

            if batch.options.versions > 1 {
                Stepper(value: $batch.previewVersion, in: 1...batch.options.versions) {
                    Text("Versão \(batch.previewVersion)/\(batch.options.versions)").font(.caption).monospacedDigit()
                }
                .controlSize(.small)
                .disabled(batch.running)
            }

            Button {
                if let id = batch.selectedID { batch.reroll(id) }
            } label: {
                Label("Re-randomizar Preview", systemImage: "dice")
            }
            .disabled(batch.selected == nil || batch.running)
            .help("Sorteia outros valores para esta imagem (outra direção das linhas, outro serrilhado, outro deslocamento) dentro dos mesmos limites")

            Button("Fechar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let item = batch.selected {
                    Text(item.url.lastPathComponent).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                }
                if batch.previewLoading { ProgressView().controlSize(.mini) }
                Spacer()
                Text(mode == .curtain
                     ? "Arraste a barra para comparar · arraste a imagem para mover (com zoom)"
                     : "Arraste a imagem para mover as duas ao mesmo tempo (com zoom)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if batch.options.texturePreset == .off {
                Text("As texturas estão desligadas. Escolha Sutil, Equilibrado, Intenso ou Personalizado em \"Texturas, linhas e bordas\" para ver linhas, serrilhado, aberração e bloom aqui.")
                    .font(.caption).foregroundStyle(Brand.warning)
            }
            if !batch.previewSummary.isEmpty {
                Text(batch.previewSummary).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("100% = um pixel da imagem para cada pixel da tela. O arquivo final tem exatamente estes pixels.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tela de comparação (AppKit)

/// SwiftUI só repassa as imagens; o desenho, o zoom e o arrastar ficam numa NSView (controle fino do pixel e do cursor).
struct StoryInspectorCanvas: NSViewRepresentable {
    var before: CGImage?
    var after: CGImage?
    var beforeLabel: String
    var mode: StoryInspectMode
    var zoom: StoryInspectZoom

    func makeNSView(context: Context) -> StoryInspectorNSView { StoryInspectorNSView() }

    func updateNSView(_ view: StoryInspectorNSView, context: Context) {
        view.beforeLabel = beforeLabel
        view.before = before
        view.after = after
        view.mode = mode
        view.zoom = zoom
    }
}

final class StoryInspectorNSView: NSView {
    var before: CGImage? { didSet { needsDisplay = true } }
    var after: CGImage? { didSet { needsDisplay = true } }
    var beforeLabel = "ANTES" { didSet { needsDisplay = true } }
    var mode: StoryInspectMode = .curtain {
        didSet {
            guard mode != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var zoom: StoryInspectZoom = .fit {
        didSet {
            guard zoom != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Ponto da imagem (em pixels, de cima para baixo) que fica no centro de cada painel quando há zoom.
    private var center = CGPoint(x: CGFloat(StoryOptimizer.width) / 2, y: CGFloat(StoryOptimizer.height) / 2)
    /// Posição da barra da cortina (0 a 1 da largura).
    private var split: CGFloat = 0.5
    private enum Drag { case none, pan, divider }
    private var drag: Drag = .none
    private var lastPoint = CGPoint.zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var imageSize: CGSize {
        if let a = after { return CGSize(width: CGFloat(a.width), height: CGFloat(a.height)) }
        if let b = before { return CGSize(width: CGFloat(b.width), height: CGFloat(b.height)) }
        return CGSize(width: CGFloat(StoryOptimizer.width), height: CGFloat(StoryOptimizer.height))
    }

    private var backing: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Retângulo de cada painel: a tela toda na cortina; as duas metades (com 6pt de vão) no lado a lado.
    private var panels: [CGRect] {
        switch mode {
        case .curtain:
            return [bounds]
        case .sideBySide:
            let gap: CGFloat = 6
            let half = (bounds.width - gap) / 2
            return [CGRect(x: 0, y: 0, width: half, height: bounds.height),
                    CGRect(x: half + gap, y: 0, width: half, height: bounds.height)]
        }
    }

    /// Pontos de tela por pixel da imagem. 100% = 1 pixel da imagem por pixel real da tela (descontando a tela Retina).
    private func scale(for panel: CGRect) -> CGFloat {
        switch zoom {
        case .fit: return max(min(panel.width / imageSize.width, panel.height / imageSize.height), 0.01)
        default: return CGFloat(zoom.rawValue) / 100 / backing
        }
    }

    private var effectiveCenter: CGPoint {
        zoom == .fit ? CGPoint(x: imageSize.width / 2, y: imageSize.height / 2) : center
    }

    // MARK: Desenho

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor(white: 0.07, alpha: 1).setFill()
        bounds.fill()

        switch mode {
        case .curtain:
            let panel = bounds
            let x = (panel.width * split).rounded()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: x, height: panel.height))
            drawImage(before, in: panel, ctx)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x, y: 0, width: panel.width - x, height: panel.height))
            drawImage(after, in: panel, ctx)
            ctx.restoreGState()
            drawDivider(at: x, in: panel, ctx)
            drawLabel(beforeLabel, at: CGPoint(x: 12, y: 12))
            drawLabel("DEPOIS", at: CGPoint(x: panel.width - 12, y: 12), alignRight: true)
        case .sideBySide:
            let rects = panels
            let images = [before, after]
            let labels = [beforeLabel, "DEPOIS"]
            for i in 0..<2 {
                ctx.saveGState()
                ctx.clip(to: rects[i])
                drawImage(images[i], in: rects[i], ctx)
                ctx.restoreGState()
                drawLabel(labels[i], at: CGPoint(x: rects[i].minX + 12, y: 12))
            }
        }
    }

    private func drawImage(_ image: CGImage?, in panel: CGRect, _ ctx: CGContext) {
        guard let image else {
            drawPlaceholder("Gerando a imagem…", in: panel)
            return
        }
        let s = scale(for: panel)
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let c = effectiveCenter
        let ox = panel.midX - c.x * s, oy = panel.midY - c.y * s
        let imageRect = CGRect(x: 0, y: 0, width: iw, height: ih)
        // só o trecho visível da imagem (em pixels) é recortado e desenhado
        let visible = CGRect(x: (panel.minX - ox) / s, y: (panel.minY - oy) / s, width: panel.width / s, height: panel.height / s)
            .intersection(imageRect)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return }
        let src = CGRect(x: floor(visible.minX), y: floor(visible.minY),
                         width: ceil(visible.maxX) - floor(visible.minX), height: ceil(visible.maxY) - floor(visible.minY))
            .intersection(imageRect)
        guard !src.isNull, let crop = image.cropping(to: src) else { return }
        let target = CGRect(x: ox + src.minX * s, y: oy + src.minY * s, width: src.width * s, height: src.height * s)
        ctx.saveGState()
        // com zoom, sem suavizar: cada pixel da imagem vira um quadrado, para ver o serrilhado de verdade
        ctx.interpolationQuality = zoom == .fit ? .high : .none
        // a NSView é invertida (y para baixo): vira o desenho para a imagem não sair de cabeça para baixo
        ctx.translateBy(x: target.minX, y: target.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        ctx.restoreGState()
    }

    private func drawDivider(at x: CGFloat, in panel: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: panel.height))
        ctx.strokePath()
        let handle = CGRect(x: x - 15, y: panel.midY - 15, width: 30, height: 30)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: handle)
        ctx.restoreGState()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.black]
        let arrows = "◂▸" as NSString
        let size = arrows.size(withAttributes: attrs)
        arrows.draw(at: CGPoint(x: handle.midX - size.width / 2, y: handle.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawLabel(_ text: String, at point: CGPoint, alignRight: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        let pill = CGRect(x: alignRight ? point.x - size.width - 16 : point.x, y: point.y, width: size.width + 16, height: size.height + 8)
        NSColor(white: 0, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        str.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 4), withAttributes: attrs)
    }

    private func drawPlaceholder(_ text: String, in panel: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: panel.midX - size.width / 2, y: panel.midY - size.height / 2), withAttributes: attrs)
    }

    // MARK: Mouse

    private var dividerX: CGFloat { (bounds.width * split).rounded() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastPoint = p
        // na cortina, a barra anda quando o clique é perto dela ou quando não há zoom (nada para mover na imagem)
        if mode == .curtain, zoom == .fit || abs(p.x - dividerX) < 16 {
            drag = .divider
            moveDivider(to: p.x)
        } else {
            drag = .pan
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .divider:
            moveDivider(to: p.x)
        case .pan:
            pan(byScreenDX: p.x - lastPoint.x, dy: p.y - lastPoint.y)
        case .none:
            break
        }
        lastPoint = p
    }

    override func mouseUp(with event: NSEvent) { drag = .none }

    override func scrollWheel(with event: NSEvent) {
        pan(byScreenDX: event.scrollingDeltaX, dy: event.scrollingDeltaY)
    }

    private func moveDivider(to x: CGFloat) {
        guard bounds.width > 0 else { return }
        split = min(max(x / bounds.width, 0.02), 0.98)
        needsDisplay = true
    }

    /// Arrastar a imagem para a direita mostra o que está à esquerda: o centro anda no sentido contrário.
    private func pan(byScreenDX dx: CGFloat, dy: CGFloat) {
        guard zoom != .fit, let panel = panels.first else { return }
        let s = scale(for: panel)
        center.x = min(max(center.x - dx / s, 0), imageSize.width)
        center.y = min(max(center.y - dy / s, 0), imageSize.height)
        needsDisplay = true
    }

    override func resetCursorRects() {
        if mode == .curtain {
            addCursorRect(CGRect(x: dividerX - 10, y: 0, width: 20, height: bounds.height), cursor: .resizeLeftRight)
        }
        if zoom != .fit {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}
