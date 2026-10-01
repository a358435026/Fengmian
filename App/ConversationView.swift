import SwiftUI
import AVFoundation

struct ConversationView: View {
    @StateObject private var model = ConversationModel()
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var editing: Turn?
    @State private var typed = ""
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationView {
            content
                .navigationTitle("自由对话").navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationTools }
                .sheet(isPresented: $showSettings) { SettingsView(model: model) }
                .sheet(isPresented: $showLibrary) { ArchiveView() }
                .sheet(item: $editing) { TurnEditor(model: model, turn: $0) }
                .confirmationDialog("是否将本次录音和双语文字保存在本机？", isPresented: $model.awaitingSaveChoice, titleVisibility: .visible) {
                    saveActions
                } message: { Text("保存后可从左上角文件夹查看或导出。录音不会发送到 DeepSeek；在线系统识别可能向 Apple 发送音频。") }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).accentColor(TranslatorDesign.blue)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.endConversation() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { model.endConversation() }
            }
            .onChange(of: scenePhase) { phase in if phase == .background { model.endConversation() } }
    }
    private var content: some View {
        VStack(spacing: 10) {
            languageRow
            conversationList
            controls
            typedInput
        }.padding(.bottom, 8).background(TranslatorDesign.background.ignoresSafeArea())
    }
    private var languageRow: some View {
        HStack {
            languagePicker($model.left)
            Button { let previous = model.left; model.left = model.right; model.right = previous } label: { Image(systemName: "arrow.left.arrow.right") }.disabled(model.busy || model.hasUnsavedSession)
            languagePicker($model.right)
        }.padding(.horizontal)
    }
    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.turns.isEmpty { introduction }
                    ForEach(model.turns) { turn in
                        TurnCard(turn: turn, model: model, edit: { editing = turn }).id(turn.id)
                    }
                    if model.phase == .recording && !model.partials.isEmpty { liveTranscript }
                }.padding()
            }.onChange(of: model.turns.count) { _ in
                if let id = model.turns.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }
    private var introduction: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 44)).foregroundColor(.blue)
            Text("让对话跨越语言").font(.title2.bold())
            Text("双方轮流说所选语言\n原文与译文逐段显示\n结束后可保存本地录音和文字")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 45)
    }
    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("正在识别 · 原文仍可能修订").font(.caption).foregroundColor(.secondary)
            ForEach(model.partials) { candidate in Text("\(candidate.language.name)：\(candidate.text)").font(.callout) }
        }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
    }
    private var controls: some View {
        VStack(spacing: 10) {
            VoiceRibbon(level: model.phase == .recording ? model.level : 0)
            if let message = model.message { Text(message).font(.caption).foregroundColor(.orange).padding(.horizontal) }
            if model.phase == .recording || model.phase == .finishing { audioMeter }
            Text(model.status).font(.caption).foregroundColor(.secondary)
            recordButton
            if model.hasUnsavedSession && model.phase == .idle {
                HStack {
                    Button("保存录音和文字") { model.saveSession() }.disabled(!model.canSave)
                    Spacer()
                    Button("不保留录音") { model.discardRecording() }
                }.font(.caption).padding(.horizontal)
            }
        }
    }
    private var audioMeter: some View {
        HStack {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60)).font(.callout.monospacedDigit())
            ProgressView(value: model.level).tint(.blue)
        }.padding(.horizontal)
    }
    private var recordButton: some View {
        Button {
            if model.phase == .recording || model.phase == .requestingPermission { model.endConversation() }
            else { model.startConversation() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32, weight: .medium)).foregroundColor(.white)
                    .frame(width: 78, height: 78).background(TranslatorDesign.gradient).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: TranslatorDesign.blue.opacity(0.4), radius: 15)
                Text(model.phase == .recording ? "结束并选择保存" : "开始自由对话 →")
                    .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(TranslatorDesign.gradient).cornerRadius(24)
            }
        }.buttonStyle(.plain).disabled(model.phase == .finishing || model.phase == .saving).padding(.horizontal)
    }
    private var typedInput: some View {
        VStack(spacing: 5) {
            HStack {
                TextField("也可以输入文字", text: $typed).textFieldStyle(.roundedBorder)
                Button("翻译") { model.translateTyped(typed); typed = "" }
                    .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.phase == .saving)
            }.padding(.horizontal)
            Text("文字：\(model.currentSourceIsLeft ? model.left.name : model.right.name) → \(model.currentSourceIsLeft ? model.right.name : model.left.name) · 点此切换")
                .font(.caption2).foregroundColor(.secondary).onTapGesture { model.currentSourceIsLeft.toggle() }
        }
    }
    @ToolbarContentBuilder private var navigationTools: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { showLibrary = true } label: { Image(systemName: "folder") }.disabled(model.busy).accessibilityLabel("本地对话")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button { model.clear() } label: { Image(systemName: "trash") }.disabled(model.busy).accessibilityLabel("清空")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.disabled(model.busy).accessibilityLabel("设置")
            }
        }
    }
    private var saveActions: some View {
        Group {
            Button("保存录音和文字") { model.saveSession() }.disabled(!model.canSave)
            Button("不保留录音", role: .destructive) { model.discardRecording() }
            Button("稍后决定", role: .cancel) {}
        }
    }
    private func languagePicker(_ selection: Binding<SpokenLanguage>) -> some View {
        Picker("语言", selection: selection) { ForEach(SpokenLanguage.all) { Text($0.name).tag($0) } }
            .pickerStyle(.menu).disabled(model.busy || model.hasUnsavedSession).frame(maxWidth: .infinity).padding(.vertical, 5).background(TranslatorDesign.panel).clipShape(Capsule())
    }
}

private struct TurnCard: View {
    let turn: Turn
    @ObservedObject var model: ConversationModel
    let edit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%02d:%02d", Int(turn.startedAt) / 60, Int(turn.startedAt) % 60)).font(.caption.monospacedDigit())
                Text("\(turn.source.name) → \(turn.target.name)").font(.caption)
                Spacer()
            }.foregroundColor(.secondary)
            Text(turn.original).font(.title3).textSelection(.enabled)
            transcript
            actions
            if turn.failed { Text("请检查 API 设置，或修正原文后重试").font(.caption).foregroundColor(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
    }
    @ViewBuilder private var transcript: some View {
        if turn.needsConfirmation {
            Label("原文待核对 · 试译", systemImage: "exclamationmark.bubble").font(.caption).foregroundColor(.orange)
        }
        Text(turn.translation.isEmpty ? (turn.failed ? "翻译失败，请重试" : "正在翻译…") : turn.translation)
            .font(.system(size: 20, weight: .medium)).foregroundColor(TranslatorDesign.blue).textSelection(.enabled)
    }
    private var actions: some View {
        HStack {
            Button(turn.needsConfirmation ? "核对原文和语言" : "修正原文 / 重译", action: edit)
                .font(.caption).disabled(model.phase == .saving)
            Spacer()
            if let elapsed = turn.elapsed { Text(String(format: "翻译 %.2f 秒", elapsed)).font(.caption2).foregroundColor(.secondary) }
            Button { model.replay(turn) } label: { Image(systemName: "speaker.wave.2") }
                .disabled(turn.translation.isEmpty || turn.pending || turn.failed || turn.needsConfirmation || model.busy)
        }
    }
}

struct TurnEditor: View {
    @ObservedObject var model: ConversationModel
    let turn: Turn
    @State private var text: String
    @State private var language: SpokenLanguage
    @Environment(\.dismiss) private var dismiss
    init(model: ConversationModel, turn: Turn) {
        self.model = model; self.turn = turn
        _text = State(initialValue: turn.original); _language = State(initialValue: turn.source)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("核对说话语言") {
                    Picker("语言", selection: $language) { Text(model.left.name).tag(model.left); Text(model.right.name).tag(model.right) }
                }
                Section("原文（请按实际听到的内容修正）") { TextEditor(text: $text).frame(minHeight: 160) }
                if !turn.alternatives.isEmpty {
                    Section("识别候选") {
                        ForEach(turn.alternatives) { candidate in
                            Button { text = candidate.text; language = candidate.language } label: {
                                VStack(alignment: .leading) { Text(candidate.language.name).font(.caption); Text(candidate.text) }
                            }
                        }
                    }
                }
                Button("确认原文并翻译") { model.confirm(id: turn.id, original: text, language: language); dismiss() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("核对原文").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.navigationViewStyle(.stack)
    }
}
