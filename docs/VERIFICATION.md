# 当前验证记录

验证日期：2026-10-01，Linux 工作区。

已通过：
- Python 探针语法编译和 --help。
- 未提供 Key 时探针在联网前退出（退出码 2），不泄露凭据。
- IPA 脚本 bash -n。
- Linux 调用 IPA 脚本明确拒绝构建（退出码 1），不会生成假的安装包。
- project.yml、GitHub workflow YAML 解析。
- workflow 内所有 run 的 shell 语法。
- project sources 与文档链接目标存在。

未执行：
- Xcode 编译、XCTest SSE 单元测试与 iOS Release 构建：环境没有 macOS/Xcode。
- DeepSeek 实际调用、费用或延迟验证：未配置 API Key。
- 麦克风/语音识别/播报/连续监听/取消任务真机验收。
- iOS 18 语言包下载和断网测试。
- TrollStore 安装、旧系统框架弱链接、Keychain 和 Speech 权限验收。

当前不应标记为生产可用，也没有生成 IPA。首次 macOS 构建若暴露 SDK 或类型问题，需以编译器结果修正后继续验收。
