# 验证记录

验证日期：2026-10-01。

## 已执行

- GitHub macOS runner，Xcode 16.4 / iOS 18.5 SDK，deployment target iOS 15.0。
- 模拟器 XCTest：7 tests，0 failures；包括 UTF-8 分片/SSE 事件、完整译文、认证失败、无 Key、截断、连接未完成。接口测试使用本机 URLProtocol mock，没有真实 API 费用。
- iphoneos Release 编译成功，生成 IPA。
- IPA 检查：标准 Payload/*.app，Info.plist MinimumOSVersion 15.0，Mach-O arm64 最低版本 15.0.0。
- 麦克风与 Speech 权限说明存在。Translation.framework 是 LC_LOAD_WEAK_DYLIB，可选加载。
- IPA 内主可执行文件权限为可执行，未打包 .env 文件。
- Python 探针和 IPA 校验器语法检查、构建脚本/workflow shell 语法检查通过。

[构建与测试日志](https://github.com/a358435026/Fengmian/actions/runs/36906252475)

构建分支：translator-ios-build，远程源码提交：0b2c627ab1ed5ad0108aba42089b66193f7ad81e。主分支保持不变。

IPA SHA-256：`dcc159a943f914a50a1cc707c6c33bd8ac61d1928aadeff85eab3f066e0160b3`。

## 未执行

- 实体 iOS 15 巨魔安装与启动、Keychain 保存、麦克风/识别/播报/音频路由验收。
- 真实 DeepSeek 调用、余额/网络/端到端时延测试：用户密钥仅在安装后由用户填写。
- iOS 18 语言包下载和断网测试；iOS 15 使用 DeepSeek 文字翻译。
- 双语自动语音判断和旧系统离线第三方翻译模型尚未实现，本版以两侧语言按钮明确方向。

模拟器测试与最低系统静态检查，不代表已在 iOS 15 真机完成验收。
