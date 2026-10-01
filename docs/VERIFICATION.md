# 0.2.0（build 7）验证记录

验证日期：2026-10-01。

[最终构建](https://github.com/a358435026/Fengmian/actions/runs/36915885041)，源代码提交 `6c44da175892aab8dd5ed18b8b18630d911165df`。

## 已执行

- macOS GitHub runner，Xcode 16.4，iOS 18.5 SDK。
- 相同核心源文件的 SwiftPM XCTest：14 项、0 失败；流式 UTF-8/SSE、认证/空 Key/截断/中断、双语保守判定、收句、M4A+TXT+JSON 保存、待确认标记、不覆盖已有文件。
- 录音导出测试使用合成音频，翻译接口使用 URLProtocol mock；未调用真实 Apple Speech 或 DeepSeek。
- 最终 iphoneos Release 编译成功，全部 SwiftUI 和 SpeechService 源码参与编译。
- 生成标准 Payload/*.app IPA，最低 Info.plist iOS 15.0；Mach-O arm64 最低 iOS 15.0.0。
- 版本 0.2.0、build 7；麦克风与语音识别权限描述存在；主可执行文件 0755；不含 XCTest bundle。
- 下载的 IPA 和 GitHub runner 的 SHA-256 一致。
- 新版不依赖 iOS 18 Translation.framework。
- 原仓库主分支 SHA 保持 `7fd66d3351020fff17a6b1c98000b0d576d0cb0e`，只修改独立分支。

SHA-256：`5c52ed2cabe23da79b24e4fc626f3788311c08ea7390d551f4aca822f5da208d`。

## 未执行与实际限制

- 新版实体 iOS 15 巨魔安装、权限/Keychain/麦克风/播报、持续双语系统识别。
- 真实音频 WER/CER、语言方向错误率、待确认比例、完整 P50/P95；不能据此承诺识别率提升或零点几秒端到端。
- 两个系统 ASR 的稳定并发与系统服务请求限制，仍需实测。
- 本机保存位于 App 私有 Documents，通过 App 内导出访问；不声称“文件”自动出现 App 根目录。
- 默认不播报；自动播报会暂缓识别。手动锁屏/退后台会结束，录音期间防止自动锁屏。
- iOS 15 文字翻译仍使用 DeepSeek，不提供离线翻译包。

一次早期 iOS 模拟器尝试卡在启动阶段并被取消；后续核心测试在 macOS 运行，不能标为新版 iOS 模拟器或真机识别测试已通过。
