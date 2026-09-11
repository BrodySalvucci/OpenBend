import SwiftUI

/// View-local state. A class rather than @State so the app also builds with Command Line Tools,
/// which ship without the SwiftUI macro plugin.
@Observable
final class SettingsUIState {
    var launchAtLogin = LaunchAtLogin.isEnabled
}

private enum BendPalette {
    static let violet = Color(red: 0.56, green: 0.42, blue: 0.85)
    static let plum = Color(red: 0.22, green: 0.12, blue: 0.31)
    static let pink = Color(red: 0.90, green: 0.59, blue: 0.73)
}

struct SettingsView: View {
    @Bindable var settings: Settings
    let controller: BendController
    @Bindable var ui: SettingsUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    styleSection
                }
                .frame(width: 328)
                VStack(alignment: .leading, spacing: 16) {
                    tuningSection
                    lidSection
                }
                .frame(maxWidth: .infinity)
            }
            generalSection
            HStack(spacing: 6) {
                Image(systemName: "escape")
                Text("Press Esc while bending to pause.")
                Spacer()
                Text("Made for the MacBook hinge")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 740)
        .tint(BendPalette.violet)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [BendPalette.violet, BendPalette.plum], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenBend").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("A little magic in every close.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in statusBadge }
        }
    }

    private var statusBadge: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Group {
                if !ScreenPermission.isGranted {
                    Label("Screen Recording off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if settings.isPaused {
                    Label("Paused", systemImage: "pause.circle.fill").foregroundStyle(.secondary)
                } else if controller.isVisible {
                    Label("Bending", systemImage: "sparkle").foregroundStyle(BendPalette.violet)
                } else if controller.isCapturing {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label(controller.captureError ?? "Starting…", systemImage: "circle.dotted")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.primary.opacity(0.04), in: Capsule())
            Text(controller.sensor.isAvailable ? String(format: "Lid %.0f°", controller.sensorAngle) : "Manual control available")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 220, alignment: .trailing)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Meet Duo.").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Clear at the hinge. Soft toward the edge.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkles").font(.system(size: 19)).foregroundStyle(BendPalette.pink)
            }
            .padding(.horizontal, 18).padding(.top, 17)
            FoldedDesktop(style: .duo)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .frame(height: 108)
            HStack(spacing: 5) {
                Capsule().fill(BendPalette.pink.opacity(0.9)).frame(width: 14, height: 2)
                Text("ANCHORED TO YOUR BOTTOM HINGE")
                    .font(.system(size: 8, weight: .medium)).tracking(1.1)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
        }
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(red: 0.19, green: 0.15, blue: 0.30), BendPalette.plum, Color(red: 0.10, green: 0.09, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duo: clear at the MacBook’s bottom hinge, progressively softer toward the top edge.")
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionTitle("Choose your feel")
                Spacer()
                if settings.style == .custom {
                    Label("Custom", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach([BendStyle.duo, .silk, .shade, .frost]) { style in
                    StyleCard(style: style, selected: settings.style == style) { settings.style = style }
                }
            }
        }
    }

    private var tuningSection: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    sectionTitle("Fine-tune")
                    Spacer()
                    Text(settings.style.title).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                LabeledSlider(title: "Perspective", value: $settings.perspective, symbol: "perspective")
                LabeledSlider(title: "Blur", value: $settings.blur, symbol: "drop.halffull")
                LabeledSlider(title: "Shadow", value: $settings.shadow, symbol: "moon.fill")
            }
        }
    }

    private var lidSection: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Move with the lid")
                HStack {
                    Text("Clears at").font(.system(size: 11))
                    Spacer()
                    Text(String(format: "%.0f°", settings.clearAngle))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                Slider(value: $settings.clearAngle, in: 40...115, step: 1)
                    .accessibilityLabel("Clear angle")
                    .accessibilityValue(String(format: "%.0f degrees", settings.clearAngle))
                Text("Bends below this angle. Clears as you open.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                Toggle("Follow the lid", isOn: $settings.followLid)
                    .toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 11))
                    .disabled(!controller.sensor.isAvailable)
                if !settings.followLid || !controller.sensor.isAvailable {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Manual angle").font(.system(size: 11))
                            Spacer()
                            Text(String(format: "%.0f°", settings.manualAngle))
                                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.manualAngle, in: 0...130, step: 1)
                            .accessibilityLabel("Manual lid angle")
                            .accessibilityValue(String(format: "%.0f degrees", settings.manualAngle))
                    }
                }
                Button { controller.runPreview() } label: {
                    Label("Preview Bend", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.isPaused || !controller.isCapturing)
                .help("Plays a close-and-open without touching the lid.")
                Text("Try the full motion without moving your Mac.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var generalSection: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    Toggle("Sound", isOn: $settings.soundEnabled)
                        .help("Play a click when the desktop clears.")
                    Divider().frame(height: 15)
                    Toggle("Launch at login", isOn: Binding(
                        get: { ui.launchAtLogin },
                        set: { LaunchAtLogin.set($0); ui.launchAtLogin = LaunchAtLogin.isEnabled }
                    ))
                    Divider().frame(height: 15)
                    Toggle("Pause effect", isOn: $settings.isPaused)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 11))
                if !ScreenPermission.isGranted {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.orange)
                        Text("Allow Screen Recording to bring your desktop into the effect.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Open Settings") { ScreenPermission.openSystemSettings() }
                        Button("Relaunch") { ScreenPermission.relaunch() }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }
}

private struct SettingsPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct StyleCard: View {
    let style: BendStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                FoldedDesktop(style: style)
                    .padding(.horizontal, 12).padding(.top, 2)
                    .frame(height: 49)
                    .background(LinearGradient(colors: [BendPalette.plum.opacity(0.94), Color(red: 0.12, green: 0.12, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                HStack {
                    Text(style.title).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? BendPalette.violet : Color.secondary.opacity(0.3))
                }
            }
            .padding(8)
            .background(selected ? BendPalette.violet.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .stroke(selected ? BendPalette.violet.opacity(0.85) : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(style.blurb)
        .accessibilityLabel(style.title + ". " + style.blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small, illustrative desktop. The lower edge stays sharp and anchored; Duo softens upward.
private struct FoldedDesktop: View {
    let style: BendStyle

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                Ellipse().fill(BendPalette.pink.opacity(0.20))
                    .frame(width: width * 0.85, height: height * 0.15)
                    .blur(radius: 7).offset(y: 3)
                ZStack {
                    DesktopTiles(style: style)
                    if style == .shade {
                        LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    }
                    if style == .frost { Color.white.opacity(0.13) }
                }
                .clipShape(FoldedSurface())
                .overlay(FoldedSurface().stroke(.white.opacity(0.22), lineWidth: 0.8))
                .padding(.bottom, 7)
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.08), BendPalette.pink.opacity(0.80), .white.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * 0.88, height: 1.5)
                    .padding(.bottom, 6)
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

/// Perspective is drawn directly, so native window snapshots preserve the artwork geometry.
private struct FoldedSurface: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { path in
            path.move(to: CGPoint(x: w * 0.16, y: h * 0.10))
            path.addQuadCurve(to: CGPoint(x: w * 0.19, y: h * 0.04), control: CGPoint(x: w * 0.17, y: h * 0.04))
            path.addLine(to: CGPoint(x: w * 0.81, y: h * 0.04))
            path.addQuadCurve(to: CGPoint(x: w * 0.84, y: h * 0.10), control: CGPoint(x: w * 0.83, y: h * 0.04))
            path.addLine(to: CGPoint(x: w * 0.97, y: h * 0.90))
            path.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.98), control: CGPoint(x: w * 0.99, y: h * 0.98))
            path.addLine(to: CGPoint(x: w * 0.06, y: h * 0.98))
            path.addQuadCurve(to: CGPoint(x: w * 0.03, y: h * 0.90), control: CGPoint(x: w * 0.01, y: h * 0.98))
            path.closeSubpath()
        }
    }
}

private struct DesktopTiles: View {
    let style: BendStyle
    private let appColors: [Color] = [.green, .blue, .orange, .pink, .purple, .cyan]

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.45), BendPalette.pink.opacity(0.78), BendPalette.plum]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h))
            hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.43), control: CGPoint(x: w * 0.45, y: h * 0.50))
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.closeSubpath()
            context.fill(hill, with: .color(BendPalette.plum.opacity(0.85)))
            context.drawLayer { desktop in
                if style == .frost { desktop.addFilter(.blur(radius: w * 0.011)) }
                desktop.drawLayer { widgets in
                    if style == .duo { widgets.addFilter(.blur(radius: w * 0.023)) }
                    let frames = [
                        CGRect(x: w * 0.19, y: h * 0.15, width: w * 0.28, height: h * 0.36),
                        CGRect(x: w * 0.51, y: h * 0.15, width: w * 0.13, height: h * 0.36),
                        CGRect(x: w * 0.68, y: h * 0.15, width: w * 0.13, height: h * 0.36),
                    ]
                    let colors: [Color] = [.white.opacity(0.63), Color(red: 0.20, green: 0.42, blue: 0.81), BendPalette.pink]
                    for index in frames.indices {
                        widgets.fill(Path(roundedRect: frames[index], cornerRadius: w * 0.02), with: .color(colors[index]))
                    }
                }
                let iconWidth = w * 0.071
                let dock = CGRect(x: w * 0.21, y: h * 0.67, width: w * 0.58, height: h * 0.24)
                desktop.fill(Path(roundedRect: dock, cornerRadius: w * 0.02), with: .color(.white.opacity(0.12)))
                for index in appColors.indices {
                    let icon = CGRect(x: w * 0.232 + CGFloat(index) * w * 0.092, y: h * 0.70, width: iconWidth, height: h * 0.18)
                    desktop.fill(Path(roundedRect: icon, cornerRadius: w * 0.015), with: .color(appColors[index].opacity(0.93)))
                    let mark = CGRect(x: icon.midX - iconWidth * 0.17, y: icon.midY - iconWidth * 0.17, width: iconWidth * 0.34, height: iconWidth * 0.34)
                    desktop.fill(Path(ellipseIn: mark), with: .color(.white.opacity(0.88)))
                }
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11)).frame(width: 99, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: 0...1)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.0f percent", value * 100))
            Text(String(format: "%.0f", value * 100))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 23, alignment: .trailing)
        }
    }
}

struct PermissionView: View {
    let controller: BendController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.dashed.badge.record").font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Screen Recording").font(.title3.weight(.semibold))
                    Text("OpenBend draws a live copy of your desktop while the lid closes.")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Open System Settings → Privacy & Security → Screen Recording.")
                step(2, "Turn on OpenBend.")
                step(3, "Relaunch OpenBend when macOS asks.")
            }
            Text("Frames are processed on this Mac. Nothing is recorded, saved or uploaded.")
                .font(.caption).foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("Open System Settings") { ScreenPermission.openSystemSettings() }
                Button("Relaunch OpenBend") { ScreenPermission.relaunch() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}
