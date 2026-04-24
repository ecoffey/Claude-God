// MenuBarRingView.swift
// Apple Watch Activity-style concentric rings for the Icon+ menubar mode.
// Uses Canvas (Core Graphics path drawing) so it renders correctly in the
// MenuBarExtra label — composited SwiftUI Circles distort in that context.

import SwiftUI

// MARK: - Multi-ring menubar icon (Canvas-based)

struct MenuBarRingView: View {

    /// Quota objects available for look-up.
    let quotas: [UsageQuota]
    /// Up to 3 quota labels to display. Empty string = unused slot.
    let labels: [String]

    // ── Apple Watch Activity ring palette ──
    // outer = Move (red), mid = Exercise (green), inner = Stand (cyan)
    static let ringColors: [Color] = [
        Color(red: 1.00, green: 0.31, blue: 0.25),
        Color(red: 0.31, green: 0.90, blue: 0.46),
        Color(red: 0.05, green: 0.73, blue: 0.93),
    ]

    // ── Layout constants ──
    private static let canvasSize: CGFloat = 20   // icon bounding box
    private static let lineWidth:  CGFloat = 2.0
    private static let step:       CGFloat = 2.5  // radial distance between ring centres

    // Resolved (progress 0-1, color) pairs — only non-empty matched labels
    private var rings: [(progress: Double, color: Color)] {
        labels.prefix(3).enumerated().compactMap { i, label in
            guard !label.isEmpty,
                  let q = quotas.first(where: { $0.label == label })
            else { return nil }
            return (progress: min(q.utilization / 100.0, 1.0),
                    color: Self.ringColors[i % Self.ringColors.count])
        }
    }

    var body: some View {
        if rings.isEmpty {
            // Fallback: plain circled-C when nothing is configured
            Image(systemName: "c.circle")
                .font(.system(size: 14, weight: .regular))
        } else {
            Canvas { ctx, size in
                let cx = size.width  / 2
                let cy = size.height / 2
                let center = CGPoint(x: cx, y: cy)

                for (i, ring) in rings.enumerated() {
                    // Outer ring uses the full radius; each inner ring steps inward
                    let radius = (size.width / 2)
                                 - Self.lineWidth / 2
                                 - CGFloat(i) * Self.step
                    guard radius > Self.lineWidth / 2 else { continue }

                    // ── Dim track (full circle) ──
                    var track = Path()
                    track.addArc(center: center, radius: radius,
                                 startAngle: .degrees(0),
                                 endAngle:   .degrees(360),
                                 clockwise: false)
                    ctx.stroke(track,
                               with: .color(ring.color.opacity(0.22)),
                               lineWidth: Self.lineWidth)

                    // ── Progress arc (12-o'clock → clockwise) ──
                    guard ring.progress > 0 else { continue }
                    var arc = Path()
                    arc.addArc(center: center, radius: radius,
                               startAngle: .degrees(-90),
                               endAngle:   .degrees(-90 + 360.0 * ring.progress),
                               clockwise: false)
                    ctx.stroke(arc,
                               with: .color(ring.color),
                               style: StrokeStyle(lineWidth: Self.lineWidth,
                                                  lineCap: .round))
                }
            }
            .frame(width: Self.canvasSize, height: Self.canvasSize)
        }
    }
}

// MARK: - Settings preview (larger, labeled)

private struct SingleRingArc: View {
    let progress: Double
    let color: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

struct RingSettingsPreview: View {
    let quotas: [UsageQuota]
    let labels: [String]

    private static let outerDiameter: CGFloat = 44
    private static let lineWidth:     CGFloat = 4.5
    private static let step:          CGFloat = 5.5

    private var rings: [(label: String, progress: Double, color: Color)] {
        labels.prefix(3).enumerated().compactMap { i, label in
            guard !label.isEmpty else { return nil }
            let util = quotas.first(where: { $0.label == label })?.utilization ?? 0
            return (label: label,
                    progress: min(util / 100.0, 1.0),
                    color: MenuBarRingView.ringColors[i % MenuBarRingView.ringColors.count])
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Ring diagram
            ZStack {
                if rings.isEmpty {
                    Image(systemName: "c.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(rings.indices, id: \.self) { i in
                        let diam = Self.outerDiameter - CGFloat(i) * Self.step * 2
                        SingleRingArc(progress: rings[i].progress,
                                      color:    rings[i].color,
                                      diameter: max(diam, 4),
                                      lineWidth: Self.lineWidth)
                    }
                }
            }
            .frame(width: Self.outerDiameter, height: Self.outerDiameter)

            // Legend
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(MenuBarRingView.ringColors[i])
                            .frame(width: 7, height: 7)
                        if i < labels.count && !labels[i].isEmpty {
                            let label = labels[i]
                            let util  = quotas.first(where: { $0.label == label })?.utilization
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            if let u = util {
                                Text("\(Int(u))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("—")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
