import SwiftUI
import AVFoundation

private struct ShareFiles: Identifiable { let id = UUID(); let urls: [URL] }
struct ArchiveView: View {
    @State private var conversations = LocalArchive.list()
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var share: ShareFiles?
    @State private var message: String?
    @State private var search = ""
    @State private var selected: SavedConversation?
    private var filtered: [SavedConversation] { conversations.filter { search.isEmpty || $0.turns.contains { $0.original.localizedCaseInsensitiveContains(search) || $0.translation.localizedCaseInsensitiveContains(search) } } }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
              VStack(alignment: .leading, spacing: 14) {
                TextField("搜索原文或译文", text: $search).textFieldStyle(.roundedBorder)
                if conversations.isEmpty { Text("尚无本地保存的对话").foregroundColor(.secondary) }
                if let message { Text(message).foregroundColor(.orange) }
                ForEach(filtered) { conversation in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { selected = conversation } label: { Label(conversation.date.formatted(date: .abbreviated, time: .shortened), systemImage: "bubble.left.and.bubble.right").font(.headline) }
                        Text(conversation.date, style: .time).font(.caption)
                        Text("\(conversation.left.name) ↔ \(conversation.right.name)").font(.caption)
                        Text(String(format: "%02d:%02d · %d 段对话", Int(conversation.duration) / 60, Int(conversation.duration) % 60, conversation.turns.count)).font(.caption).foregroundColor(.secondary)
                        HStack {
                            Button(playingID == conversation.id ? "停止播放" : "播放录音") { play(conversation) }.buttonStyle(.bordered)
                            Button("导出录音和文字") { share = .init(urls: LocalArchive.files(conversation)) }.buttonStyle(.bordered)
                        }.font(.caption)
                        Button("删除本地记录", role: .destructive) {
                            player?.stop(); playingID = nil
                            do { try LocalArchive.delete(conversation); conversations = LocalArchive.list() }
                            catch { message = error.localizedDescription }
                        }.font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                }
              }.padding()
            }.background(TranslatorDesign.background.ignoresSafeArea()).navigationTitle("历史记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $selected) { ArchiveDetailView(conversation: $0) }
                .sheet(item: $share) { FileShareView(urls: $0.urls) }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).accentColor(TranslatorDesign.blue).onDisappear { player?.stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
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

struct ArchiveDetailView: View {
    let conversation: SavedConversation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(conversation.date, style: .date).foregroundColor(.secondary)
                    ForEach(conversation.turns) { turn in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(turn.source.name) → \(turn.target.name)").font(.caption).foregroundColor(.secondary)
                            Text(turn.original).font(.headline).textSelection(.enabled)
                            if turn.needsConfirmation { Text("原文待核对 · 试译").font(.caption).foregroundColor(.orange) }
                            Text(turn.translation.isEmpty ? "无译文" : turn.translation).foregroundColor(TranslatorDesign.blue).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
                    }
                }.padding()
            }.background(TranslatorDesign.background.ignoresSafeArea()).navigationTitle("对话详情")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
    }
}
