import SwiftUI
import AVFoundation

struct ConversationView: View {
    @StateObject private var model = ConversationModel()
    @State private var showSettings = false
    @State private var typed = ""
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack {
                    languagePicker($model.left)
                    Button {
                        model.stop()
                        let previousLeft = model.left
                        model.left = model.right
                        model.right = previousLeft
                    } label: { Image(systemName: "arrow.left.arrow.right") }
                    languagePicker($model.right)
                }.padding(.horizontal)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if model.turns.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 44)).foregroundColor(.blue)
                                    Text("面对面，自由交流").font(.title2.bold())
                                    Text("双方分别点自己的语言说话\n支持文字输入和译文播报").foregroundColor(.secondary).multilineTextAlignment(.center)
                                }.frame(maxWidth: .infinity).padding(.top, 70)
                            }
                            ForEach(model.turns) { turn in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(turn.source.name) → \(turn.target.name)").font(.caption).foregroundColor(.secondary)
                                    Text(turn.original).foregroundColor(.secondary).textSelection(.enabled)
                                    Text(turn.translation.isEmpty ? (turn.failed ? "翻译未完成" : "…") : turn.translation)
                                        .font(.title3).textSelection(.enabled)
                                    HStack {
                                        if let elapsed = turn.elapsed {
                                            Text(String(format: "翻译 %.2f 秒", elapsed)).font(.caption2).foregroundColor(.secondary)
                                        }
                                        if let first = turn.firstToken {
                                            Text(String(format: "首字 %.2f 秒", first)).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button { model.replay(turn) } label: { Image(systemName: "speaker.wave.2") }
                                            .disabled(turn.translation.isEmpty || turn.failed || model.busy)
                                    }
                                    if turn.failed { Text("未完成 · 请重新提交原文").font(.caption).foregroundColor(.orange) }
                                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.blue.opacity(0.06)).cornerRadius(16).id(turn.id)
                            }
                        }.padding()
                    }
                    .onChange(of: model.turns.count) { _ in if let id = model.turns.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                if !model.partial.isEmpty { Text(model.partial).font(.callout).padding(.horizontal) }
                if let message = model.message { Text(message).font(.caption).foregroundColor(.orange).padding(.horizontal) }
                Text(model.status).font(.caption).foregroundColor(.secondary)
                HStack(spacing: 14) {
                    micButton(left: true)
                    if model.busy { Button { model.stop() } label: { Image(systemName: "stop.fill").foregroundColor(.red) }.accessibilityLabel("停止") }
                    micButton(left: false)
                }.padding(.horizontal)
                HStack {
                    TextField("输入文字也可翻译", text: $typed).textFieldStyle(.roundedBorder)
                    Button("翻译") {
                        model.translate(typed, fromLeft: model.currentSourceIsLeft); typed = ""
                    }.disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                }.padding(.horizontal)
                Text("文字方向：\(model.currentSourceIsLeft ? model.left.name : model.right.name) → \(model.currentSourceIsLeft ? model.right.name : model.left.name)")
                    .font(.caption2).foregroundColor(.secondary)
                    .onTapGesture { if !model.busy { model.currentSourceIsLeft.toggle() } }
            }
            .padding(.bottom, 8).navigationTitle("自由对话").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button { model.clear() } label: { Image(systemName: "trash") }.accessibilityLabel("清空对话") }
                ToolbarItem(placement: .navigationBarTrailing) { Button { model.stop(); showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置") }
            }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            .background(Group { if #available(iOS 18.0, *) { OfflineBridge(model: model) } })
        }.navigationViewStyle(.stack)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in model.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { model.stop() }
            }
            .onChange(of: scenePhase) { phase in if phase != .active { model.stop() } }
    }
    private func languagePicker(_ selection: Binding<SpokenLanguage>) -> some View {
        Picker("语言", selection: selection) {
            ForEach(SpokenLanguage.all) { Text($0.name).tag($0) }
        }.pickerStyle(.menu).disabled(model.busy).frame(maxWidth: .infinity)
    }
    private func micButton(left: Bool) -> some View {
        Button { model.microphone(fromLeft: left) } label: {
            Label(left ? model.left.name : model.right.name, systemImage: "mic.fill")
                .font(.callout.bold()).frame(maxWidth: .infinity).padding(.vertical, 18)
        }.buttonStyle(.borderedProminent).tint(left ? .blue : .indigo)
            .disabled(model.phase == .requestingPermission || model.phase == .translating || model.phase == .speaking)
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
                    Text("文字发往 DeepSeek；在线系统语音识别可能发往 Apple。对话只保存在本次内存中，密钥不上传其他服务器。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("对话") {
                    Toggle("自动播报译文", isOn: $model.autoSpeak)
                    Toggle("播报后继续监听当前语言", isOn: $model.continuous)
                    Text("换人说话时点击另一侧语言；第一版不自动判断说话语言。连续监听时也可以随时停止。")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: $model.silence, in: 0.5...1.6, step: 0.1)
                    Text(String(format: "停顿 %.1f 秒后收句", model.silence)).font(.caption)
                }
                Section("离线") {
                    Toggle("只使用设备端语音识别", isOn: $model.offlineASR)
                    if #available(iOS 18.0, *) {
                        Toggle("使用系统离线翻译", isOn: $model.offlineTranslation)
                        Button("准备当前语言组合的翻译包") { dismiss(); model.prepareOffline() }
                    } else {
                        Text("本系统不支持 Apple 离线翻译，文字翻译使用 DeepSeek。")
                    }
                    Text("离线识别、翻译和声音是三种独立能力。语言是否支持由系统决定；请预先下载并断网实测，不支持时会提示，不会自动联网兜底。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("识别提示词（每行一个）") {
                    TextEditor(text: $model.hints).frame(minHeight: 90)
                    Text("可填写姓名、地名、行业术语。提示词有助于识别，不保证准确。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).onAppear { key = KeyStore.read() }
    }
}
