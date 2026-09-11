import SwiftUI
import AppKit

/// Onboarding state. A class rather than @State so the app also builds with Command Line Tools.
@Observable
final class OnboardingState {
    enum Stage: Int { case welcome, permission, done }
    var stage: Stage = .welcome
    var permissionGranted = ScreenPermission.isGranted
    var capturing = false
}

/// First-run flow: what OpenBend does, the Screen Recording grant, and a done screen.
@MainActor
struct OnboardingView: View {
    @Bindable var state: OnboardingState
    let controller: BendController
    let onFinish: () -> Void

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch state.stage {
                case .welcome: welcome.transition(pageTransition)
                case .permission: permission.transition(pageTransition)
                case .done: done.transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.4), value: state.stage)
            pageDots
                .padding(.top, 14)
        }
        .padding(.top, 34)
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
        .frame(width: 480, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BendArt.heroGradient)
                FoldedDesktop(style: .duo)
                    .padding(.horizontal, 40)
                    .padding(.top, 34)
                    .padding(.bottom, 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(BendArt.pink)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 220)
            .accessibilityHidden(true)

            Text("Your desktop bends\nas you close the lid.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text("OpenBend holds the picture in place and slides the screen over it like a pane of glass, softening as it goes. Open the lid and it snaps back.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 10)
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                FeatureChip(symbol: "laptopcomputer", text: "Hinge sensor")
                FeatureChip(symbol: "cpu", text: "Rendered live")
                FeatureChip(symbol: "lock.shield", text: "Stays on your Mac")
            }
            .padding(.top, 18)

            Spacer(minLength: 16)

            Button {
                state.stage = .permission
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var permission: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BendArt.heroGradient)
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            Text("Allow Screen Recording")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .padding(.top, 18)
            Text("OpenBend needs to see the desktop to draw it bending. Frames are processed on this Mac and are never recorded or uploaded.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.horizontal, 8)

            VStack(spacing: 0) {
                StepRow(number: 1, text: "Open System Settings → Privacy & Security → Screen Recording")
                SettingsDivider()
                StepRow(number: 2, text: "Turn on OpenBend")
                SettingsDivider()
                StepRow(number: 3, text: "Choose Quit & Reopen when macOS asks")
            }
            .background(SettingsChrome.groupFill, in: RoundedRectangle(cornerRadius: SettingsChrome.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SettingsChrome.cornerRadius, style: .continuous)
                .strokeBorder(SettingsChrome.groupStroke, lineWidth: 1))
            .padding(.top, 22)

            permissionStatus
                .padding(.top, 16)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                if state.permissionGranted {
                    Button {
                        ScreenPermission.relaunch()
                    } label: {
                        Text("Relaunch OpenBend").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        ScreenPermission.openSystemSettings()
                    } label: {
                        Text("Open System Settings").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                HStack {
                    Button("Back") { state.stage = .welcome }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Skip for now") { onFinish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 2)
            }
        }
    }

    private var permissionStatus: some View {
        HStack(spacing: 8) {
            if state.permissionGranted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Permission granted. Relaunch OpenBend to finish.")
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.25), value: state.permissionGranted)
    }

    private var done: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            ZStack {
                Circle().fill(Color.green.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)
            Text("You're all set.")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .padding(.top, 22)
            Text("Lower the lid a little to see it bend. OpenBend lives in the menu bar; press Esc while it's bending to pause, or use Preview Bend in Settings to watch it without moving your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 10)
                .padding(.horizontal, 8)
            Spacer(minLength: 16)
            Button {
                onFinish()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == state.stage.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == state.stage.rawValue ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.3), value: state.stage)
        .accessibilityHidden(true)
    }
}

private struct FeatureChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SettingsChrome.groupFill, in: Capsule())
        .overlay(Capsule().strokeBorder(SettingsChrome.groupStroke, lineWidth: 1))
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Text(text).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
