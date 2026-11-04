import SwiftUI
import AppKit

enum Brand {
    static let red = Color(red: 1.0, green: 0.2, blue: 0.2)
    static let surface = Color(white: 0.11)
    static let surfaceRaised = Color(white: 0.15)
    static let stroke = Color.white.opacity(0.08)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let success = Color(red: 0.3, green: 0.85, blue: 0.5)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.stroke))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var symbol: String
    var tint: Color = .secondary
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(label, systemImage: symbol).font(.callout).foregroundStyle(tint)
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }
    }
}

struct StatePill: View {
    let state: JobState
    var color: Color {
        switch state {
        case .running: return Brand.red
        case .review: return Brand.warning
        case .exported: return Brand.success
        case .paused, .queued: return .gray
        case .cancelled: return .gray.opacity(0.6)
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(state.label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }
}

/// Miniatura carregada fora da thread principal.
struct Thumb: View {
    let url: URL?
    var maxPixel: Int = 480
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.35))
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if url != nil {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let px = maxPixel
            image = await Task.detached(priority: .userInitiated) { ImageTools.thumbnail(url, maxPixel: px) }.value
        }
    }
}

struct WarningLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Brand.warning)
            .lineLimit(3)
            .help(text)
    }
}

struct ErrorLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "xmark.octagon.fill")
            .font(.caption)
            .foregroundStyle(Brand.red)
            .lineLimit(3)
            .help(text)
    }
}

extension Double {
    var usd: String { String(format: "US$ %.2f", self) }
}

extension Date {
    var short: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: self)
    }
}
