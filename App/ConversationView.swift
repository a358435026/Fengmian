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
            VStack(spacing: 10) {
                HStack {
                    languagePicker($model.left)
                    Image(systemName: "arrow.left.arrow.right").foregroundColor(.secondary)
                    languagePicker($model.right)
                }.padding(.horizontal)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if model.turns.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "waveform").font(.system(size: 44)).foregroundColor(.blue)
                                    Text("开始一次，自然对话").font(.title2.bold())
                                    Text("双方轮流说所选语言\n原文与译文逐段显示\n结束后可保存本地录音和文字")
                                        .foregroundColor(.secondary).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity).padding(.top, 45)
                            }
                            ForEach(model.turns) { turn in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(String(format: "%02d:%02d", Int(turn.startedAt) / 60, Int(turn.startedAt) % 60)).font(.caption.monospacedDigit())
                                        Text("\(turn.source.name) → \(turn.target.name)").font(.caption)
                                        Spacer()
                                    }.foregroundColor(.secondary)
                                    Text(turn.original).font(.title3).textSelection(.enabled)
                                    if turn.needsConfirmation {
                                        Label("识别待确认", systemImage: "exclamationmark.bubble").font(.callout).foregroundColor(.orange)
                                        ForEach(turn.alternatives) { candidate in
                                            Text("\(candidate.language.name)：\(candidate.text)").font(.caption).foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text(turn.translation.isEmpty ? (turn.failed ? "翻译未完成" : "正在翻译…") : turn.translation)
                                            .foregroundColor(.blue).textSelection(.enabled)
                                    }
                                    HStack {
                                        Button(turn.needsConfirmation ? "核对原文和语言" : "修正原文 / 重译") { editing = turn }
                                            .font(.caption).disabled(model.phase == .saving)
                                        Spacer()
                                        if let elapsed = turn.elapsed { Text(String(format: "翻译 %.2f 秒", elapsed)).font(.caption2).foregroundColor(.secondary) }
                                        Button { model.replay(turn) } label: { Image(systemName: "speaker.wave.2") }
                                            .disabled(turn.translation.isEmpty || turn.pending || turn.failed || turn.needsConfirmation || model.busy)
                                    }
                                    if turn.failed { Text("未完成，请核对原文后重试").font(.caption).foregroundColor(.orange) }
                                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                    .background(turn.needsConfirmation ? Color.orange.opacity(0.08) : Color.blue.opacity(0.06))
                                    .cornerRadius(16).id(turn.id)
                            }
                            if model.phase == .recording && !model.partials.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("正在识别 · 原文仍可能修订").font(.caption).foregroundColor(.secondary)
                                    ForEach(model.partials) { candidate in Text("\(candidate.language.name)：\(candidate.text)").font(.callout) }
                                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.gray.opacity(0.08)).cornerRadius(12)
                            }
                        }.padding()
                    }.onChange(of: model.turns.count) { _ in
                        if let id = model.turns.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                if let message = model.message { Text(message).font(.caption).foregroundColor(.orange).padding(.horizontal) }
                if model.phase == .recording || model.phase == .finishing {
                    HStack {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60)).font(.callout.monospacedDigit())
                        ProgressView(value: model.level).tint(.blue)
                    }.padding(.horizontal)
                }
                Text(model.status).font(.caption).foregroundColor(.secondary)
                Button {
                    if model.phase == .recording || model.phase == .requestingPermission { model.endConversation() }
                    else { model.startConversation() }
                } label: {
                    Label(model.phase == .recording ? "结束对话" : "开始自由对话", systemImage: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                }.buttonStyle(.borderedProminent).tint(model.phase == .recording ? .red : .blue)
                    .disabled(model.phase == .finishing || model.phase == .saving).padding(.horizontal)
                if model.hasUnsavedSession && model.phase == .idle {
                    HStack {
                        Button("保存录音和文字") { model.saveSession() }.disabled(!model.canSave)
                        Spacer()
                        Button("不保留录音") { model.discardRecording() }
                    }.font(.caption).padding(.horizontal)
                }
                HStack {
                    TextField("也可以输入文字", text: $typed).textFieldStyle(.roundedBorder)
                    Button("翻译") { model.translateTyped(typed); typed = "" }
                        .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.phase == .saving)
                }.padding(.horizontal)
                Text("文字：\(model.currentSourceIsLeft ? model.left.name : model.right.name) → \(model.currentSourceIsLeft ? model.right.name : model.left.name) · 点此切换")
                    .font(.caption2).foregroundColor(.secondary).onTapGesture { model.currentSourceIsLeft.toggle() }
            }.padding(.bottom, 8).navigationTitle("自由对话").navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                .sheet(isPresented: $showSettings) { SettingsView(model: model) }
                .sheet(isPresented: $showLibrary) { ArchiveView() }
                .sheet(item: $editing) { TurnEditor(model: model, turn: $0) }
                .confirmationDialog("是否将本次录音和双语文字保存在本机？", isPresented: $model.awaitingSaveChoice, titleVisibility: .visible) {
                    Button("保存录音和文字") { model.saveSession() }.disabled(!model.canSave)
                    Button("不保留录音", role: .destructive) { model.discardRecording() }
                    Button("稍后决定", role: .cancel) {}
                } message: { Text("保存后可从左上角文件夹查看或导出。录音不会发送到 DeepSeek；在线系统识别可能向 Apple 发送音频。") }
        }.navigationViewStyle(.stack)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.endConversation() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { model.endConversation() }
            }
            .onChange(of: model.phase) { phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .recording || phase == .finishing || phase == .saving
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: scenePhase) { phase in if phase == .background { model.endConversation() } }
    }
    private func languagePicker(_ selection: Binding<SpokenLanguage>) -> some View {
        Picker("语言", selection: selection) { ForEach(SpokenLanguage.all) { Text($0.name).tag($0) } }
            .pickerStyle(.menu).disabled(model.busy || model.hasUnsavedSession).frame(maxWidth: .infinity)
    }
}

struct SettingsView: View {
    @ObservedObject var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var keyMessage = ""
    var body: some View {
        NavigationView {
            Form {
                Section("DeepSeek 官方 API") {
                    SecureField("API 密钥", text: $key).textInputAutocapitalization(.never).disableAutocorrection(true)
                    Button("保存密钥") {
                        do { try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); keyMessage = "已保存到本机钥匙串" }
                        catch { keyMessage = error.localizedDescription }
                    }
                    if !keyMessage.isEmpty { Text(keyMessage).font(.caption) }
                    Text("原文及少量已确认对话上下文发往 DeepSeek。在线系统识别可能向 Apple 发送音频。保留的录音和文字只存本机，是否导出由你选择。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("持续对话") {
                    Toggle("自动播报译文", isOn: $model.autoSpeak)
                    Text("默认只显示译文，保持连续识别。开启播报后，录音继续，但播报期间暂缓识别，避免自己的译音被再次翻译。")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: $model.silence, in: 0.9...2.2, step: 0.1)
                    Text(String(format: "停顿 %.1f 秒后收句，再等待最终修订", model.silence)).font(.caption)
                    Text("准确率优先，默认 1.3 秒。短词、混说、两个识别候选相近时保留原文并标为待确认，不自动翻译或播报。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("识别") {
                    Toggle("只使用设备端识别", isOn: $model.offlineASR)
                    Text("两个所选语言都必须被系统支持。iOS 15 的文字翻译使用联网 DeepSeek。双语判定使用系统识别候选，实际准确率需真机检验。")
                        .font(.caption).foregroundColor(.secondary)
                    Text("声音清晰、适中即可；过响会失真。外放测试请避免另一台设备同时收音或播报，先关闭自动播报做基线测试。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("姓名、地名、产品与行业词（每行一个）") {
                    TextEditor(text: $model.hints).frame(minHeight: 90)
                    Text("原文可以核对和修正。翻译提示词保留数字、单位、否定和不确定语气，不用猜测补写错误原文。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).onAppear { key = KeyStore.read() }
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
