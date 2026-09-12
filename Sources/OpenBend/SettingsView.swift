import SwiftUI
import AppKit

/// View-local state. A class rather than @State so the app also builds with Command Line Tools,
/// which ship without the SwiftUI macro plugin.
@Observable
final class SettingsUIState {
    var launchAtLogin = LaunchAtLogin.isEnabled
}

/// Colors used only inside artwork. Controls use the system accent so they match the Mac.
enum BendArt {
    static let violet = Color(red: 0.56, green: 0.42, blue: 0.85)
    static let plum = Color(red: 0.22, green: 0.12, blue: 0.31)
    static let pink = Color(red: 0.90, green: 0.59, blue: 0.73)
    static let night = Color(red: 0.10, green: 0.09, blue: 0.15)
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.19, green: 0.15, blue: 0.30), plum, night],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Grouped-form surfaces that follow the Mac's appearance, like System Settings.
enum SettingsChrome {
    static let groupFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.055)
            : NSColor.white.withAlphaComponent(0.72)
    })
    static let groupStroke = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.08)
    })
    static let cornerRadius: CGFloat = 10
}

// MARK: - Settings

@MainActor
struct SettingsView: View {
    @Bindable var settings: Settings
    let controller: BendController
    @Bindable var ui: SettingsUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            styleSection
            lidSection
            generalSection
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)      // clears the traffic lights under the transparent title bar
        .padding(.bottom, 14)
        .frame(width: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenBend")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                Text("Your desktop bends as you close the lid.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(status: status)
                    Text(controller.sensor.isAvailable
                         ? String(format: "Lid %.0f°", controller.sensorAngle)
                         : "No lid sensor")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var status: AppStatus {
        if !ScreenPermission.isGranted { return .needsPermission }
        if settings.isPaused { return .paused }
        if controller.isVisible { return .bending }
        if controller.isCapturing { return .ready }
        return .starting(controller.captureError)
    }

    // MARK: Style

    private var styleSection: some View {
        SettingsSection("Style", accessory: AnyView(previewButton)) {
            HStack(spacing: 10) {
                ForEach([BendStyle.duo, .trueDuo, .silk, .shade, .frost]) { style in
                    StyleCard(style: style, selected: settings.style == style) {
                        settings.style = style
                    }
                }
            }
            .padding(10)
            SettingsDivider()
            SliderRow("Perspective", value: $settings.perspective, range: 0...1, format: percent)
            SettingsDivider()
            SliderRow("Blur", value: $settings.blur, range: 0...1, format: percent)
            SettingsDivider()
            SliderRow("Shadow", value: $settings.shadow, range: 0...1, format: percent)
        } caption: {
            if settings.style == .custom {
                Text("Custom mix. Pick a style above to go back to a preset.")
            } else {
                Text(settings.style.blurb)
            }
        }
    }

    private var previewButton: some View {
        Button {
            controller.runPreview()
        } label: {
            Label("Preview Bend", systemImage: "play.fill")
                .font(.system(size: 11, weight: .medium))
        }
        .controlSize(.small)
        .disabled(settings.isPaused || !controller.isCapturing)
        .help("Play a close-and-open without moving the lid.")
    }

    // MARK: Lid

    private var lidSection: some View {
        SettingsSection("Lid") {
            SliderRow("Starts after", value: $settings.activationTravel, range: 1...15, step: 1, format: degrees)
            SettingsDivider()
            SliderRow("Keeps bending below", value: $settings.stayOnBelow, range: 40...100, step: 1, format: degrees)
            SettingsDivider()
            SliderRow("Relaxes after", value: $settings.settleDelay, range: 0.5...3, step: 0.25, format: seconds)
            SettingsDivider()
            SettingsRow("Follow the lid",
                        subtitle: controller.sensor.isAvailable ? nil : "No lid angle sensor on this Mac") {
                Toggle("", isOn: $settings.followLid)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!controller.sensor.isAvailable)
            }
            if !settings.followLid || !controller.sensor.isAvailable {
                SettingsDivider()
                SliderRow("Angle", value: $settings.manualAngle, range: 0...130, step: 1, format: degrees)
            }
        } caption: {
            Text("The bend begins once the lid has come down this far. Stop above the stay-on angle and it relaxes away after the rest time, so you can keep working. Below that angle it holds.")
        }
    }

    // MARK: General

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Click when the desktop clears") {
                Toggle("", isOn: $settings.soundEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsDivider()
            SettingsRow("Launch at login") {
                Toggle("", isOn: Binding(
                    get: { ui.launchAtLogin },
                    set: { LaunchAtLogin.set($0); ui.launchAtLogin = LaunchAtLogin.isEnabled }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsDivider()
            SettingsRow("Pause OpenBend") {
                Toggle("", isOn: $settings.isPaused)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsDivider()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                SettingsRow("Screen Recording", subtitle: "Needed to capture the desktop. Frames stay on this Mac.") {
                    if ScreenPermission.isGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 10) {
                            Label("Not allowed", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                            Button("Open Settings…") { ScreenPermission.openSystemSettings() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text("OpenBend \(Self.version)")
            Text("·")
            Link("GitHub", destination: URL(string: "https://github.com/BrodySalvucci/OpenBend")!)
            Spacer()
            Label("Esc pauses while bending", systemImage: "escape")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private func degrees(_ value: Double) -> String { String(format: "%.0f°", value) }
    private func seconds(_ value: Double) -> String { String(format: "%.2g s", value) }
}

// MARK: - Status

enum AppStatus {
    case needsPermission, paused, bending, ready, starting(String?)

    var title: String {
        switch self {
        case .needsPermission: "Needs Screen Recording"
        case .paused: "Paused"
        case .bending: "Bending"
        case .ready: "Ready"
        case .starting(let error): error == nil ? "Starting…" : "Not capturing"
        }
    }

    var color: Color {
        switch self {
        case .needsPermission: .orange
        case .paused: .secondary
        case .bending: BendArt.violet
        case .ready: .green
        case .starting(let error): error == nil ? .secondary : .orange
        }
    }
}

struct StatusPill: View {
    let status: AppStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.title).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(SettingsChrome.groupFill, in: Capsule())
        .overlay(Capsule().strokeBorder(SettingsChrome.groupStroke, lineWidth: 1))
        .animation(.snappy(duration: 0.25), value: status.title)
        .accessibilityLabel("Status: \(status.title)")
    }
}

// MARK: - Grouped form pieces

struct SettingsSection<Content: View, Caption: View>: View {
    let title: String
    var accessory: AnyView?
    @ViewBuilder let content: Content
    @ViewBuilder let caption: Caption

    init(_ title: String, accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder caption: () -> Caption) {
        self.title = title
        self.accessory = accessory
        self.content = content()
        self.caption = caption()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 2)
                Spacer()
                accessory
            }
            VStack(spacing: 0) { content }
                .background(SettingsChrome.groupFill, in: RoundedRectangle(cornerRadius: SettingsChrome.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SettingsChrome.cornerRadius, style: .continuous)
                    .strokeBorder(SettingsChrome.groupStroke, lineWidth: 1))
            caption
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }
}

extension SettingsSection where Caption == EmptyView {
    init(_ title: String, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: accessory, content: content, caption: { EmptyView() })
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, subtitle == nil ? 7 : 6)
    }
}

struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    init(_ title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>,
         step: Double? = nil, format: @escaping (Double) -> String) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Group {
                    if let step {
                        Slider(value: $value, in: range, step: step)
                    } else {
                        Slider(value: $value, in: range)
                    }
                }
                .frame(width: 170)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
                Text(format(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}

// MARK: - Style cards

private struct StyleCard: View {
    let style: BendStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                FoldedDesktop(style: style)
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [BendArt.plum.opacity(0.94), BendArt.night],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                HStack(spacing: 6) {
                    Text(style.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
                }
            }
            .padding(7)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : SettingsChrome.groupStroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.snappy(duration: 0.22), value: selected)
        }
        .buttonStyle(PressableCardStyle())
        .help(style.blurb)
        .accessibilityLabel(style.title + ". " + style.blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Instant press feedback without a hover model (which would need @State).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Artwork

/// A small illustrative desktop on a tilted panel. The lower edge stays sharp and anchored;
/// each style shows its own treatment toward the top. True Duo shows the same panel with the
/// picture dissolving into black past the desktop's edges.
struct FoldedDesktop: View {
    let style: BendStyle

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let surface = FoldedSurface()
            ZStack(alignment: .bottom) {
                Ellipse().fill(BendArt.pink.opacity(0.22))
                    .frame(width: width * 0.85, height: height * 0.15)
                    .blur(radius: 7).offset(y: 3)
                ZStack {
                    DesktopTiles(style: style)
                    if style == .shade {
                        LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    }
                    if style == .frost { Color.white.opacity(0.13) }
                    if style == .trueDuo {
                        LinearGradient(colors: [.black, .black.opacity(0)],
                                       startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62))
                        LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0)],
                                       startPoint: .leading, endPoint: UnitPoint(x: 0.22, y: 0.5))
                        LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0)],
                                       startPoint: .trailing, endPoint: UnitPoint(x: 0.78, y: 0.5))
                    }
                }
                .clipShape(surface)
                .overlay(surface.stroke(.white.opacity(0.22), lineWidth: 0.8))
                .padding(.bottom, 7)
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.08), BendArt.pink.opacity(0.80), .white.opacity(0.08)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * 0.88, height: 1.5)
                    .padding(.bottom, 6)
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

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
                Gradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.45), BendArt.pink.opacity(0.78), BendArt.plum]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h))
            hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.43), control: CGPoint(x: w * 0.45, y: h * 0.50))
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.closeSubpath()
            context.fill(hill, with: .color(BendArt.plum.opacity(0.85)))
            context.drawLayer { desktop in
                if style == .frost { desktop.addFilter(.blur(radius: w * 0.011)) }
                desktop.drawLayer { widgets in
                    if style == .duo || style == .trueDuo { widgets.addFilter(.blur(radius: w * 0.023)) }
                    let frames = [
                        CGRect(x: w * 0.19, y: h * 0.15, width: w * 0.28, height: h * 0.36),
                        CGRect(x: w * 0.51, y: h * 0.15, width: w * 0.13, height: h * 0.36),
                        CGRect(x: w * 0.68, y: h * 0.15, width: w * 0.13, height: h * 0.36),
                    ]
                    let colors: [Color] = [.white.opacity(0.63), Color(red: 0.20, green: 0.42, blue: 0.81), BendArt.pink]
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
