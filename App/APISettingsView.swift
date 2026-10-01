import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("darkAppearance") private var darkAppearance = false
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("清晰、自然，按你的习惯沟通").foregroundColor(.secondary)
                    Toggle("深色模式", isOn: $darkAppearance).glassPanel()
                    NavigationLink(destination: APISettingsView()) {
                        HStack {
                            Image(systemName: "server.rack").foregroundColor(TranslatorDesign.blue)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API / 模型配置").font(.headline)
                                Text("官方服务 · 自定义中转 · 翻译测试").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.foregroundColor(.primary).glassPanel()
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
        }.navigationViewStyle(.stack).preferredColorScheme(darkAppearance ? .dark : .light).accentColor(TranslatorDesign.blue)
    }
}

struct APISettingsView: View {
    @State private var configuration = APIConfiguration.load()
    @State private var key = ""
    @State private var feedback = ""
    @State private var modelFeedback = ""
    @State private var testText = "您好，请问我们明天几点见面？"
    @State private var result = ""
    @State private var testing = false
    @State private var loadingModels = false
    @State private var testTask: Task<Void, Never>?
    @State private var testStarted: Date?
    @State private var modelsTask: Task<Void, Never>?
    @State private var models: [APIModel] = []
    @State private var modelSearch = ""
    @State private var testedConfiguration: APIConfiguration?
    @State private var testedKey = ""
    @State private var saved = false
    private var busy: Bool { testing || loadingModels }
    private var canActivate: Bool { testedConfiguration == configuration && testedKey == key && !busy }
    private var visibleModels: [APIModel] {
        models.filter { modelSearch.isEmpty || $0.id.localizedCaseInsensitiveContains(modelSearch) || $0.name.localizedCaseInsensitiveContains(modelSearch) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("填写密钥 → 获取模型 → 选择 → 测试 → 启用").font(.subheadline).foregroundColor(.secondary)
                servicePanel
                credentialsPanel
                modelsPanel
                testPanel
                activationPanel
                Text("模型列表来自你配置的服务器。部分中转不提供列表，仍可手填其文档中的准确模型 ID。接口返回模型不代表都有权限或余额，需测试后启用。第三方服务会接收测试及翻译文字。").font(.caption).foregroundColor(.secondary)
            }.padding()
        }.background(TranslatorDesign.background.ignoresSafeArea()).navigationTitle("翻译模型")
            .onAppear { key = KeyStore.read(provider: configuration.provider) }
            .onDisappear { testTask?.cancel(); modelsTask?.cancel() }
            .onChange(of: configuration) { _ in invalidateTest() }
            .onChange(of: key) { _ in models = []; modelSearch = ""; modelFeedback = ""; invalidateTest() }
    }
    private var servicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("服务与地址", systemImage: "server.rack").font(.headline)
            Picker("服务商", selection: $configuration.provider) {
                ForEach(APIProvider.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.menu).disabled(busy)
                .onChange(of: configuration.provider) { provider in
                    configuration = .preset(provider); key = KeyStore.read(provider: provider)
                    models = []; modelSearch = ""; modelFeedback = ""; feedback = ""; result = ""
                }
            Picker("API 协议", selection: $configuration.format) {
                ForEach(APIWireFormat.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.menu).disabled(busy)
                .onChange(of: configuration.format) { _ in models = []; modelSearch = ""; modelFeedback = "" }
            Button("恢复该服务的默认配置") {
                configuration = .preset(configuration.provider)
                models = []; modelSearch = ""; modelFeedback = ""
                invalidateTest()
            }.font(.caption).disabled(busy)
            Text("API 地址").font(.caption).foregroundColor(.secondary)
            TextField("https://…/v1", text: $configuration.baseURL).keyboardType(.URL)
                .textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(busy)
                .onChange(of: configuration.baseURL) { _ in models = []; modelSearch = ""; modelFeedback = "" }
            Text("OpenAI 兼容地址填到 /v1 或完整 /chat/completions；DeepSeek 官方可直接填 https://api.deepseek.com。").font(.caption).foregroundColor(.secondary)
        }.glassPanel()
    }
    private var credentialsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API 密钥", systemImage: "key.fill").font(.headline)
            SecureField("粘贴你的密钥", text: $key).textInputAutocapitalization(.never).disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(busy)
            Text("密钥只在本机保存，不会放进导出文件。").font(.caption).foregroundColor(.secondary)
            Button(action: fetchModels) {
                HStack { if loadingModels { ProgressView() }; Label(loadingModels ? "正在获取模型…" : "获取可用模型", systemImage: "arrow.clockwise") }
            }.buttonStyle(.borderedProminent).disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !modelFeedback.isEmpty { Text(modelFeedback).font(.caption).foregroundColor(models.isEmpty ? TranslatorDesign.warning : .secondary) }
        }.glassPanel()
    }
    private var modelsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("选择翻译模型", systemImage: "square.stack.3d.up").font(.headline)
            if !models.isEmpty {
                TextField("搜索模型", text: $modelSearch).textFieldStyle(.roundedBorder).disabled(busy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if visibleModels.isEmpty { Text("没有匹配模型，请清空搜索词。").font(.caption).foregroundColor(.secondary) }
                        ForEach(visibleModels) { model in
                            Button { configuration.model = model.id } label: {
                                modelRow(model)
                            }.buttonStyle(.plain).disabled(busy)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 210)
            }
            Text("当前模型 ID（可手动输入，区分大小写）").font(.caption).foregroundColor(.secondary)
            TextField("例如 deepseek-flash", text: $configuration.model).textInputAutocapitalization(.never)
                .disableAutocorrection(true).textFieldStyle(.roundedBorder).disabled(busy)
            if !models.isEmpty && !models.contains(where: { $0.id == configuration.model }) {
                Label("当前 ID 不在返回列表中，请选择或核对。", systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(TranslatorDesign.warning)
            }
            if configuration.provider == .deepseek {
                Text("显示名和 API ID 可能不同，获取后点选即可。优先使用能通过翻译测试的模型。").font(.caption).foregroundColor(.secondary)
            }
        }.glassPanel()
    }
    private func modelRow(_ model: APIModel) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).font(.subheadline.weight(.medium)).foregroundColor(.primary)
                if model.name != model.id { Text(model.id).font(.caption).foregroundColor(.secondary) }
            }
            Spacer()
            Image(systemName: configuration.model == model.id ? "checkmark.circle.fill" : "circle").foregroundColor(TranslatorDesign.blue)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("测试翻译 · 中文 → 英语", systemImage: "checkmark.shield").font(.headline)
            TextEditor(text: $testText).frame(height: 75).cornerRadius(10).disabled(busy)
            Button(action: test) {
                HStack { if testing { ProgressView() }; Text(testing ? "正在请求译文…" : "测试连接与翻译") }
            }.buttonStyle(.borderedProminent).disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if testing, let started = testStarted {
                TimelineView(.periodic(from: started, by: 1)) { clock in
                    Text("已等待 \(Int(max(0, clock.date.timeIntervalSince(started)))) 秒 · 最长等待 60 秒")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if !result.isEmpty { Text(result).textSelection(.enabled) }
            if !feedback.isEmpty { Text(feedback).font(.caption).foregroundColor(canActivate || saved ? TranslatorDesign.success : TranslatorDesign.warning) }
        }.glassPanel()
    }
    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("保存并启用此配置") {
                do {
                    try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), provider: configuration.provider)
                    try configuration.save(); saved = true; feedback = "已启用，返回对话即可使用。"
                } catch { feedback = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(!canActivate)
            Text("成功收到完整译文后才能启用。获取模型和测试不会覆盖之前可用的配置。").font(.caption).foregroundColor(.secondary)
        }.glassPanel()
    }
    private func invalidateTest() {
        testedConfiguration = nil; testedKey = ""; saved = false; result = ""; feedback = ""
    }
    private func fetchModels() {
        loadingModels = true; models = []; modelSearch = ""; modelFeedback = ""
        let config = configuration; let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
        modelsTask = Task { @MainActor in
            defer { loadingModels = false }
            do {
                let received = try await DeepSeekClient().fetchModels(configuration: config, key: credential)
                guard !Task.isCancelled else { return }
                models = received
                modelFeedback = "获取到 \(received.count) 个模型，请点选后测试。"
            } catch {
                guard !Task.isCancelled else { return }
                modelFeedback = error.localizedDescription
            }
        }
    }
    private func test() {
        testing = true; testStarted = Date(); result = ""; feedback = ""; testedConfiguration = nil; saved = false
        let config = configuration; let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = testText; let began = Date()
        testTask = Task { @MainActor in
            defer { testing = false; testStarted = nil }
            do {
                try await DeepSeekClient().translate(text: text, source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: credential, configuration: config) { result += $0 }
                guard !Task.isCancelled else { return }
                testedConfiguration = config; testedKey = key
                feedback = String(format: "测试成功 · %.2f 秒。现在可以保存启用。", Date().timeIntervalSince(began))
            } catch {
                guard !Task.isCancelled else { return }
                result = ""; feedback = "测试失败：" + error.localizedDescription
            }
        }
    }
}
