import MediaPlayer
import SwiftUI
import UIKit

struct DriveMusicPanel: View {
    @State private var expanded: Bool
    @State private var showAppleMusic = false
    @State private var authorized = MPMediaLibrary.authorizationStatus() == .authorized
    private let player = MPMusicPlayerController.systemMusicPlayer

    init(initiallyExpanded: Bool = false) {
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                authorized = MPMediaLibrary.authorizationStatus() == .authorized
                expanded.toggle()
            } label: {
                Label("Media controls", systemImage: expanded ? "chevron.down" : "play.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            if expanded {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2")
                    SystemMediaVolume().frame(height: 32)
                }
                Text("For play, pause and skipping in other apps, open Control Center.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Apple Music", isExpanded: $showAppleMusic) {
                    appleMusicControls
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var appleMusicControls: some View {
        if authorized {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let title = player.nowPlayingItem?.title ?? "No track playing"
                let artist = player.nowPlayingItem?.artist
                HStack {
                    VStack(alignment: .leading) {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let artist { Text(artist).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    control("backward.fill", label: "Previous track") { player.skipToPreviousItem() }
                    let playing = player.playbackState == .playing
                    control(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play") {
                        if player.playbackState == .playing { player.pause() } else { player.play() }
                    }
                    control("forward.fill", label: "Next track") { player.skipToNextItem() }
                }
            }
        } else {
            Button("Allow Apple Music access") {
                if MPMediaLibrary.authorizationStatus() == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                } else {
                    MPMediaLibrary.requestAuthorization { status in
                        DispatchQueue.main.async { authorized = status == .authorized }
                    }
                }
            }.font(.subheadline)
        }
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct SystemMediaVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.accessibilityLabel = L10n.text("System media volume")
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
