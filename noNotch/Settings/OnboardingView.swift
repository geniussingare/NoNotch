import AppKit
import SwiftUI

/// First-launch screen: every permission in one place, asked up front.
struct OnboardingView: View {
    let permissions: Permissions
    let onDone: () -> Void

    @State private var requesting = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                Text("Welcome to noNotch")
                    .font(.system(size: 22, weight: .bold))
                Text("by GeniusSoft™")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text("Allow these once and everything just works.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    PermissionRow(kind: kind, granted: permissions.isGranted(kind)) {
                        Task { await permissions.request(kind) }
                    } openSettings: {
                        permissions.openSettings(for: kind)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05 * Double(index) + 0.1), value: appeared)
                    if index < PermissionKind.allCases.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
            .padding(.horizontal, 24)

            HStack {
                Button("Skip for Now", action: onDone)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                if permissions.allGranted {
                    Button("Get Started", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(requesting ? "Requesting…" : "Allow All") {
                        requesting = true
                        Task {
                            await permissions.requestAll()
                            requesting = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(requesting)
                }
            }
            .padding(24)
        }
        .frame(width: 460)
        // Polls only while visible; the task is cancelled when the window closes.
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: permissions.granted)
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: kind.tint)))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text(kind.reason).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Allow", action: request)
                    .controlSize(.small)
                    .contextMenu { Button("Open System Settings", action: openSettings) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
