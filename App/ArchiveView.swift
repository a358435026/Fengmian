import SwiftUI
import AVFoundation

private struct ShareFiles: Identifiable { let id = UUID(); let urls: [URL] }
struct ArchiveView: View {
    @AppStorage("darkAppearance") private var darkAppearance = false
    @State private var conversations = LocalArchive.list()
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var share: ShareFiles?
    @State private var message: String?
    @State private var search = ""
    @State private var selected: SavedConversation?
    @State private var deleteTarget: SavedConversation?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    private var filtered: [SavedConversation] {
        conversations.filter { search.isEmpty || $0.turns.contains { $0.original.localizedCaseInsensitiveContains(search) || $0.translation.localizedCaseInsensitiveContains(search) } }
    }
    var body: some View {
        NavigationView {
            content
                .navigationTitle("历史记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $selected) { ArchiveDetailView(conversation: $0) }
                .sheet(item: $share) { FileShareView(urls: $0.urls) }
                .alert("删除这段本地记录？", isPresented: $confirmDelete, presenting: deleteTarget) { conversation in
                    Button("删除", role: .destructive) { delete(conversation) }
                    Button("取消", role: .cancel) {}
                } message: { _ in Text("录音和双语文字会从本机删除。") }
        }.navigationViewStyle(.stack)
            .preferredColorScheme(darkAppearance ? .dark : .light).accentColor(TranslatorDesign.blue)
            .onDisappear { player?.stop(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                searchField
                if let message { Text(message).font(.caption).foregroundColor(TranslatorDesign.warning) }
                if conversations.isEmpty { emptyState }
                else if filtered.isEmpty { Text("没有找到匹配的对话").font(.subheadline).foregroundColor(.secondary).padding(.vertical, 24) }
                ForEach(filtered) { conversation in conversationCard(conversation) }
            }.padding(16)
        }.background(TranslatorDesign.background.ignoresSafeArea())
    }
    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索原文或译文", text: $search).font(.subheadline)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .accessibilityLabel("清除搜索")
            }
        }.padding(12).background(TranslatorDesign.inputBackground).cornerRadius(14)
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder").font(.system(size: 42, weight: .light)).foregroundColor(TranslatorDesign.blue)
                .frame(width: 88, height: 88).background(TranslatorDesign.paleBlue).clipShape(Circle())
            Text("对话，留在你的手机里").font(.headline).foregroundColor(.primary)
            Text("结束对话时选择保存\n录音与双语文字就会显示在这里")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 55)
    }
    private func conversationCard(_ conversation: SavedConversation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Button { selected = conversation } label: { cardPreview(conversation) }.buttonStyle(.plain)
                Button { play(conversation) } label: {
                    Image(systemName: playingID == conversation.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(TranslatorDesign.blue)
                        .frame(width: 36, height: 36).background(TranslatorDesign.paleBlue).clipShape(Circle())
                }.accessibilityLabel(playingID == conversation.id ? "停止播放录音" : "播放录音")
            }
            Divider().opacity(0.55)
            HStack {
                Label(String(format: "%02d:%02d · %d 段对话", Int(conversation.duration) / 60, Int(conversation.duration) % 60, conversation.turns.count), systemImage: "waveform")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button { share = .init(urls: LocalArchive.files(conversation)) } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("导出录音和双语文字")
                Button { deleteTarget = conversation; confirmDelete = true } label: { Image(systemName: "trash") }
                    .foregroundColor(.secondary).padding(.leading, 10).accessibilityLabel("删除本地记录")
            }.font(.system(size: 15))
        }.glassPanel()
    }
    private func cardPreview(_ conversation: SavedConversation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(conversation.turns.first?.original ?? "双语对话")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
            if let translation = conversation.turns.first?.translation, !translation.isEmpty {
                Text(translation).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Text("\(conversation.left.flag) \(conversation.left.name) ↔ \(conversation.right.flag) \(conversation.right.name)")
                .font(.caption2).foregroundColor(TranslatorDesign.blue).lineLimit(1).minimumScaleFactor(0.75)
            Text(conversation.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func delete(_ conversation: SavedConversation) {
        player?.stop(); playingID = nil
        do { try LocalArchive.delete(conversation); conversations = LocalArchive.list() }
        catch { message = error.localizedDescription }
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
    @AppStorage("darkAppearance") private var darkAppearance = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(conversation.turns) { turn in archivedBubble(turn) }
                }.padding(16)
            }.background(TranslatorDesign.background.ignoresSafeArea())
                .navigationTitle("对话详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(darkAppearance ? .dark : .light).accentColor(TranslatorDesign.blue)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conversation.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
            Text("\(conversation.left.flag) \(conversation.left.name) ↔ \(conversation.right.flag) \(conversation.right.name)")
                .font(.caption).foregroundColor(TranslatorDesign.blue)
            Text(String(format: "%02d:%02d · %d 段对话 · 本机保存", Int(conversation.duration) / 60, Int(conversation.duration) % 60, conversation.turns.count))
                .font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
    }
    private func archivedBubble(_ turn: Turn) -> some View {
        HStack(spacing: 0) {
            if turn.source != conversation.left { Spacer(minLength: 23) }
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("\(turn.source.flag) \(turn.source.name) → \(turn.target.name)")
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }.font(.caption2).foregroundColor(.secondary)
                Text(turn.original).font(.system(size: 17, weight: .medium)).lineSpacing(4).textSelection(.enabled)
                Divider().opacity(0.45)
                if turn.needsConfirmation {
                    Label("原文待核对 · 试译", systemImage: "exclamationmark.bubble").font(.caption).foregroundColor(TranslatorDesign.warning)
                }
                Text(turn.translation.isEmpty ? "无译文" : turn.translation)
                    .font(.system(size: 17)).lineSpacing(4).textSelection(.enabled)
            }.foregroundColor(.primary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(turn.source == conversation.left ? TranslatorDesign.paleBlue : TranslatorDesign.warmBubble)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            if turn.source == conversation.left { Spacer(minLength: 23) }
        }
    }
}
