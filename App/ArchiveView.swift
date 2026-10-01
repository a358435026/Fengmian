import SwiftUI
import AVFoundation

private struct ShareFiles: Identifiable { let id = UUID(); let urls: [URL] }
struct ArchiveView: View {
    @State private var conversations = LocalArchive.list()
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var share: ShareFiles?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                if conversations.isEmpty { Text("尚无本地保存的对话").foregroundColor(.secondary) }
                if let message { Text(message).foregroundColor(.orange) }
                ForEach(conversations) { conversation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(conversation.date, style: .date).font(.headline)
                        Text(conversation.date, style: .time).font(.caption)
                        Text("\(conversation.left.name) ↔ \(conversation.right.name)").font(.caption)
                        Text(String(format: "%02d:%02d · %d 段对话", Int(conversation.duration) / 60, Int(conversation.duration) % 60, conversation.turns.count)).font(.caption).foregroundColor(.secondary)
                        HStack {
                            Button(playingID == conversation.id ? "停止播放" : "播放录音") { play(conversation) }.buttonStyle(.bordered)
                            Button("导出录音和文字") { share = .init(urls: LocalArchive.files(conversation)) }.buttonStyle(.bordered)
                        }.font(.caption)
                    }.padding(.vertical, 6)
                }.onDelete { offsets in
                    player?.stop(); playingID = nil
                    for offset in offsets {
                        do { try LocalArchive.delete(conversations[offset]) } catch { message = error.localizedDescription }
                    }
                    conversations = LocalArchive.list()
                }
            }.navigationTitle("本地对话").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $share) { FileShareView(urls: $0.urls) }
        }.navigationViewStyle(.stack).onDisappear { player?.stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    private func play(_ conversation: SavedConversation) {
        player?.stop()
        if playingID == conversation.id { playingID = nil; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: LocalArchive.folder(conversation).appendingPathComponent("audio.m4a"))
            player?.play(); playingID = conversation.id
        } catch { message = "录音播放失败：\(error.localizedDescription)"; playingID = nil }
    }
}
struct FileShareView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
