import SwiftUI

/// Header badge that flips between "running" and "paused" tied to the
/// live `job.state` events. Hidden when the swarm isn't connected.
struct PauseStatusBadge: View {
    @ObservedObject var swarm: SwarmClient

    var body: some View {
        if swarm.isConnected || swarm.isPaused {
            HStack(spacing: 6) {
                Image(systemName: swarm.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(swarm.isPaused ? LiquidGlass.warning : LiquidGlass.success)
                Text(swarm.isPaused ? "paused" : "running")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(swarm.isPaused ? "Build paused" : "Build running")
        }
    }
}
