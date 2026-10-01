import SwiftUI
import AVFoundation

struct ConversationView: View {
    @StateObject private var model = ConversationModel()
    @AppStorage("darkAppearance") private var darkAppearance = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var showTextInput = false
    @State private var editing: Turn?
    @State private var typed = ""
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var active: Bool { model.phase == .recording || model.phase == .requestingPermission }
    private var home: Bool { model.turns.isEmpty && model.phase == .idle }
    var body: some View {
        NavigationView {
            content
                .navigationTitle(home ? "AI 对话翻译" : "自由对话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationTools }
                .sheet(isPresented: $showSettings) { SettingsView(model: model) }
                .sheet(isPresented: $showLibrary) { ArchiveView() }
                .sheet(item: $editing) { TurnEditor(model: model, turn: $0) }
                .confirmationDialog("是否将本次录音和双语文字保存在本机？", isPresented: $model.awaitingSaveChoice, titleVisibility: .visible) {
                    saveActions
                } message: { Text("保存后可从左上角历史记录查看或导出。录音不会发送到翻译 API；在线系统识别可能向 Apple 发送音频。") }
        }.navigationViewStyle(.stack)
            .preferredColorScheme(darkAppearance ? .dark : .light)
            .accentColor(TranslatorDesign.blue)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.endConversation() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { model.endConversation() }
            }
            .onChange(of: scenePhase) { phase in if phase == .background { model.endConversation() } }
    }
    private var content: some View {
        VStack(spacing: 0) {
            languageRow.padding(.top, 10).padding(.bottom, 4)
            conversationList
            controls
            if showTextInput { typedInput }
        }.padding(.bottom, 8)
            .background(TranslatorDesign.background.ignoresSafeArea())
    }
    private var languageRow: some View {
        HStack(spacing: 9) {
            languagePicker($model.left)
            Button {
                let previous = model.left; model.left = model.right; model.right = previous
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17, weight: .medium)).foregroundColor(.secondary)
                    .frame(width: 28, height: 40)
            }.disabled(model.busy || model.hasUnsavedSession).accessibilityLabel("交换两种语言")
            languagePicker($model.right)
        }.padding(.horizontal, 16)
    }
    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.turns.isEmpty { introduction }
                    ForEach(model.turns) { turn in
                        TurnCard(turn: turn, model: model, edit: { editing = turn }).id(turn.id)
                    }
                    if model.phase == .recording && !model.partials.isEmpty { liveTranscript }
                    Color.clear.frame(height: 1).id("conversationBottom")
                }.padding(.horizontal, 16).padding(.vertical, 18)
            }.onChange(of: model.turns.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversationBottom", anchor: .bottom) }
            }
        }
    }
    private var introduction: some View {
        VStack(spacing: 12) {
            Text("跨越语言，让世界更近").font(.system(size: 24, weight: .semibold)).foregroundColor(.primary)
            Text("按一次开始，双方自然轮流说话")
                .font(.subheadline).foregroundColor(.secondary)
            LanguageGlobe().padding(.vertical, 5)
            HStack(spacing: 8) {
                feature("双向对话", icon: "person.2.fill")
                feature("原文与译文", icon: "text.bubble.fill")
                feature("本地录音", icon: "lock.fill")
            }
            Text("说话、翻译、理解。简单就好。")
                .font(.caption).foregroundColor(.secondary).padding(.top, 4)
        }.frame(maxWidth: .infinity).padding(.top, 12)
    }
    private func feature(_ title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(TranslatorDesign.blue)
            Text(title).font(.caption).foregroundColor(.primary)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(TranslatorDesign.panel).cornerRadius(17)
    }
    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundColor(TranslatorDesign.blue)
                Text("正在识别，原文仍可能修订").foregroundColor(.secondary)
            }.font(.caption)
            ForEach(model.partials) { candidate in
                Text("\(candidate.language.flag) \(candidate.text)").font(.callout).foregroundColor(.primary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).glassPanel()
    }
    private var controls: some View {
        VStack(spacing: 9) {
            if let message = model.message { statusMessage(message) }
            if active || model.phase == .finishing { VoiceRibbon(level: model.phase == .recording ? model.level : 0) }
            if home { startButton } else { recordingDock }
            statusLine
            if model.hasUnsavedSession && model.phase == .idle { unsavedActions }
        }.padding(.horizontal, 18).padding(.top, 5).padding(.bottom, 7)
    }
    private func statusMessage(_ message: String) -> some View {
        Text(message).font(.caption).foregroundColor(TranslatorDesign.warning)
            .multilineTextAlignment(.center).lineLimit(4)
            .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 8)
            .background(TranslatorDesign.warmBubble).cornerRadius(12)
    }
    private var statusLine: some View {
        HStack(spacing: 7) {
            if model.phase == .recording {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                    .font(.caption.monospacedDigit())
            }
            Text(model.status).font(.caption).lineLimit(2)
        }.foregroundColor(.secondary).frame(maxWidth: .infinity)
    }
    private var startButton: some View {
        VStack(spacing: 12) {
            Button(action: toggleRecording) {
                Label("开始对话翻译", systemImage: "mic.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(TranslatorDesign.gradient).cornerRadius(20)
                    .shadow(color: TranslatorDesign.blue.opacity(0.17), radius: 10, x: 0, y: 5)
            }.buttonStyle(.plain)
            HStack {
                Button { openTextInput() } label: { Label("文字翻译", systemImage: "keyboard") }
                Spacer()
                Button { showLibrary = true } label: { Label("历史记录", systemImage: "folder") }
            }.font(.subheadline).padding(.horizontal, 12)
        }
    }
    private var recordingDock: some View {
        HStack(alignment: .center, spacing: 40) {
            Button { openTextInput() } label: { dockIcon("keyboard", label: "输入文字") }
            Button(action: toggleRecording) {
                Image(systemName: active ? "stop.fill" : "mic.fill")
                    .font(.system(size: active ? 25 : 30, weight: .medium)).foregroundColor(.white)
                    .frame(width: 68, height: 68).background(TranslatorDesign.gradient).clipShape(Circle())
                    .overlay(Circle().stroke(TranslatorDesign.blue.opacity(0.12), lineWidth: 6))
                    .shadow(color: TranslatorDesign.blue.opacity(0.18), radius: 10, x: 0, y: 5)
            }.buttonStyle(.plain).disabled(model.phase == .finishing || model.phase == .saving)
                .accessibilityLabel(active ? "结束录音并选择保存" : "开始自由对话")
            Button {
                if showTextInput && !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submitTyped() }
                else { openTextInput() }
            } label: { dockIcon("character.bubble", label: "翻译文字") }
                .disabled(model.phase == .saving)
        }.frame(maxWidth: .infinity)
    }
    private func dockIcon(_ icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 21, weight: .medium)).foregroundColor(.primary)
                .frame(width: 46, height: 46).background(TranslatorDesign.panel).cornerRadius(15)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
    private var unsavedActions: some View {
        HStack {
            Button("保存录音和文字") { model.saveSession() }.disabled(!model.canSave)
            Spacer()
            Button("不保留录音") { model.discardRecording() }
        }.font(.caption).padding(.horizontal, 3).padding(.top, 3)
    }
    private var typedInput: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                TextField("输入需要翻译的文字", text: $typed)
                    .font(.body).padding(11).background(TranslatorDesign.panel).cornerRadius(13)
                    .focused($typing).submitLabel(.send).onSubmit(submitTyped)
                Button(action: submitTyped) {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 42, height: 42).background(TranslatorDesign.blue).clipShape(Circle())
                }.disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.phase == .saving)
                    .accessibilityLabel("翻译文字")
                Button { showTextInput = false; typing = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                }.accessibilityLabel("收起文字输入")
            }
            Button { model.currentSourceIsLeft.toggle() } label: {
                Text("\(model.currentSourceIsLeft ? model.left.name : model.right.name) → \(model.currentSourceIsLeft ? model.right.name : model.left.name) · 切换")
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.padding(.horizontal, 16).padding(.top, 7)
    }
    @ToolbarContentBuilder private var navigationTools: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { showLibrary = true } label: { Image(systemName: "folder") }
                .disabled(model.busy).accessibilityLabel("本地历史记录")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 19) {
                if !model.turns.isEmpty {
                    Button { model.clear() } label: { Image(systemName: "trash") }
                        .disabled(model.busy).accessibilityLabel("清空当前对话")
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .disabled(model.busy).accessibilityLabel("设置")
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
        Menu {
            ForEach(SpokenLanguage.all) { language in
                Button { selection.wrappedValue = language } label: {
                    if language == selection.wrappedValue {
                        Label("\(language.flag) \(language.name)", systemImage: "checkmark")
                    } else { Text("\(language.flag) \(language.name)") }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.wrappedValue.flag).font(.title3)
                Text(selection.wrappedValue.name).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }.foregroundColor(.primary).frame(maxWidth: .infinity).padding(.horizontal, 9).padding(.vertical, 11)
                .background(TranslatorDesign.paleBlue.opacity(0.6)).clipShape(Capsule())
        }.disabled(model.busy || model.hasUnsavedSession).accessibilityLabel("选择语言：\(selection.wrappedValue.name)")
    }
    private func toggleRecording() {
        typing = false
        if active { model.endConversation() } else { model.startConversation() }
    }
    private func openTextInput() { showTextInput = true; typing = true }
    private func submitTyped() {
        guard model.phase != .saving, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.translateTyped(typed); typed = ""; typing = false
    }
}

private struct TurnCard: View {
    let turn: Turn
    @ObservedObject var model: ConversationModel
    let edit: () -> Void
    private var fromLeft: Bool { turn.source == model.left }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !fromLeft { Spacer(minLength: 23) }
            bubble
            if fromLeft { Spacer(minLength: 23) }
        }
    }
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 5) {
                Text(turn.source.flag)
                Text("\(turn.source.name) → \(turn.target.name)").lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }.font(.caption2).foregroundColor(.secondary)
            Text(turn.original).font(.system(size: 17, weight: .medium)).lineSpacing(4).textSelection(.enabled)
            Divider().opacity(0.45)
            transcript
            actions
        }.foregroundColor(.primary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(fromLeft ? TranslatorDesign.paleBlue : TranslatorDesign.warmBubble)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    @ViewBuilder private var transcript: some View {
        if turn.needsConfirmation {
            Label("原文待核对 · 试译", systemImage: "exclamationmark.bubble")
                .font(.caption).foregroundColor(TranslatorDesign.warning)
        }
        if turn.translation.isEmpty {
            HStack(spacing: 7) {
                if turn.pending { ProgressView().scaleEffect(0.75) }
                Text(turn.failed ? "翻译失败，请检查 API 后重试" : "正在翻译…")
                    .font(.subheadline).foregroundColor(turn.failed ? TranslatorDesign.warning : .secondary)
            }
        } else {
            Text(turn.translation).font(.system(size: 17)).lineSpacing(4).textSelection(.enabled)
        }
    }
    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: edit) {
                Label(turn.needsConfirmation ? "核对原文" : "修正 / 重译", systemImage: "square.and.pencil")
                    .font(.caption2)
            }.disabled(model.phase == .saving)
            Spacer(minLength: 0)
            if let elapsed = turn.elapsed {
                Text(String(format: "%.1f 秒", elapsed)).font(.caption2).foregroundColor(.secondary)
            }
            Button { model.replay(turn) } label: {
                Image(systemName: "speaker.wave.2").font(.system(size: 16)).frame(width: 29, height: 25)
            }.disabled(turn.translation.isEmpty || turn.pending || turn.failed || turn.needsConfirmation || model.busy)
                .accessibilityLabel("播放译文")
        }.foregroundColor(TranslatorDesign.blue)
    }
}

struct TurnEditor: View {
    @ObservedObject var model: ConversationModel
    let turn: Turn
    @AppStorage("darkAppearance") private var darkAppearance = false
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
                    Picker("语言", selection: $language) {
                        Text("\(model.left.flag) \(model.left.name)").tag(model.left)
                        Text("\(model.right.flag) \(model.right.name)").tag(model.right)
                    }
                }
                Section("原文（请按实际听到的内容修正）") { TextEditor(text: $text).frame(minHeight: 160) }
                if !turn.alternatives.isEmpty {
                    Section("识别候选") {
                        ForEach(turn.alternatives) { candidate in
                            Button { text = candidate.text; language = candidate.language } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(candidate.language.flag) \(candidate.language.name)").font(.caption)
                                    Text(candidate.text).foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                Button("确认原文并翻译") { model.confirm(id: turn.id, original: text, language: language); dismiss() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("核对原文").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(darkAppearance ? .dark : .light).accentColor(TranslatorDesign.blue)
    }
}
