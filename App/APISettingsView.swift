import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("个性化配置，让沟通更自然").foregroundColor(.secondary)
                    NavigationLink(destination: APISettingsView()) {
                        HStack {
                            Image(systemName: "server.rack").foregroundColor(TranslatorDesign.blue)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API / 模型配置").font(.headline)
                                Text("官方服务 · 自定义中转 · 翻译测试").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.foregroundColor(.white).glassPanel()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("持续双向对话", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
                        Text("一次开始，双方轮流说话。低可靠性原文会标记并显示试译，可随时修正。").font(.caption).foregroundColor(.secondary)
                        Toggle("自动播报译文", isOn: $model.autoSpeak)
                        Text("待核对试译不自动播报。正常播报时录音继续、识别暂缓，避免译音重复识别。").font(.caption).foregroundColor(.secondary)
                    }.glassPanel()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Label("停顿时长", systemImage: "timer"); Spacer(); Text(String(format: "%.1f 秒", model.silence)) }.font(.headline)
                        Slider(value: $model.silence, in: 0.9...2.2, step: 0.1)
                        Text("停顿后收句，再等待系统最终修订。过短容易切断完整句子。").font(.caption).foregroundColor(.secondary)
                    }.glassPanel()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("识别与行业词", systemImage: "waveform").font(.headline)
                        Toggle("仅设备端语音识别", isOn: $model.offlineASR)
                        Text("仅在系统支持所选语言时可用。关闭时系统识别可能将音频发给 Apple。DeepSeek 等文本模型不负责识别音频。").font(.caption).foregroundColor(.secondary)
                        Text("姓名 / 地名 / 产品词，每行一个").font(.caption)
                        TextEditor(text: $model.hints).frame(height: 90).cornerRadius(10)
                    }.glassPanel()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("隐私与本地记录", systemImage: "lock.shield").font(.headline)
                        Text("密钥存本机钥匙串。翻译原文与少量已确认上下文发送到你配置的 API；第三方中转由该服务处理。录音只在本机保存，可在结束时丢弃或自行导出。没有账户或云同步。").font(.caption).foregroundColor(.secondary)
                    }.glassPanel()
                }.padding()
            }.background(TranslatorDesign.background.ignoresSafeArea()).navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).accentColor(TranslatorDesign.blue)
    }
}

struct APISettingsView: View {
    @State private var configuration = APIConfiguration.load()
    @State private var key = ""
    @State private var feedback = ""
    @State private var testText = "您好，请问我们明天几点见面？"
    @State private var result = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                servicePanel
                credentialsPanel
                testPanel
                Text("预设仅提供默认地址和模型，请以服务商账户可用模型为准。自定义中转需选择其实际协议；API 地址为 Base URL 或兼容协议的完整端点，Gemini 填版本 Base URL。第三方服务会接收测试和翻译文本。").font(.caption).foregroundColor(.secondary)
            }.padding()
        }.background(TranslatorDesign.background.ignoresSafeArea()).navigationTitle("API / 模型配置")
            .onAppear { key = KeyStore.read(provider: configuration.provider) }
            .onDisappear { testTask?.cancel() }
    }
    private var servicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("翻译服务", systemImage: "server.rack").font(.headline)
            Picker("服务商", selection: $configuration.provider) {
                ForEach(APIProvider.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.menu).disabled(testing)
                .onChange(of: configuration.provider) { provider in
                    configuration = .preset(provider); key = KeyStore.read(provider: provider)
                    feedback = ""; result = ""
                }
            Picker("API 协议", selection: $configuration.format) {
                ForEach(APIWireFormat.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.menu).disabled(testing)
            Text("API 地址").font(.caption).foregroundColor(.secondary)
            TextField("https://…/v1", text: $configuration.baseURL).keyboardType(.URL)
                .textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(testing)
            Text("模型 ID").font(.caption).foregroundColor(.secondary)
            TextField("例如 deepseek-chat", text: $configuration.model).textInputAutocapitalization(.never)
                .disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(testing)
        }.glassPanel()
    }
    private var credentialsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("密钥与保存", systemImage: "key.fill").font(.headline)
            SecureField("API 密钥", text: $key).textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(testing)
            Button("保存并启用此配置") {
                do {
                    _ = try configuration.requestURL()
                    try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), provider: configuration.provider)
                    try configuration.save(); feedback = "已保存。请点击下方测试验证实际翻译。"
                } catch { feedback = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(testing)
            if !feedback.isEmpty { Text(feedback).font(.caption).foregroundColor(.orange) }
        }.glassPanel()
    }
    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("实际翻译测试 · 中文 → 英语", systemImage: "checkmark.shield").font(.headline)
            TextEditor(text: $testText).frame(height: 75).cornerRadius(10).disabled(testing)
            Button(action: test) {
                HStack { if testing { ProgressView() }; Text(testing ? "正在请求 API…" : "测试连接与翻译") }
            }.buttonStyle(.borderedProminent).disabled(testing || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !result.isEmpty { Text(result).textSelection(.enabled) }
            Text("测试使用当前填写的配置，不会自动保存，也不会写入对话记录。").font(.caption).foregroundColor(.secondary)
        }.glassPanel()
    }
    private func test() {
        testing = true; result = ""; feedback = ""
        let config = configuration; let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = testText; let began = Date()
        testTask = Task { @MainActor in
            defer { testing = false }
            do {
                try await DeepSeekClient().translate(text: text, source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: credential, configuration: config) { result += $0 }
                feedback = String(format: "测试成功 · 总耗时 %.2f 秒。保存后用于对话。", Date().timeIntervalSince(began))
            } catch {
                guard !Task.isCancelled else { return }
                result = ""; feedback = "测试失败：" + error.localizedDescription
            }
        }
    }
}
