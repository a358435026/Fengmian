# 自由对话 · iPhone 双向语音翻译

一个独立 SwiftUI 原生 App 项目，只做面对面对话翻译：说话 → 识别 → 翻译 → 播报。没有账户、广告、会议、照片、社交功能，不需要部署后端。

**当前交付是原生源码和构建配置，不是已验证的安装包。此 Linux 工作区没有 Xcode，尚未编译或真机测试。没有配置 API 密钥，尚未实测 DeepSeek。**

## 第一版已有实现

- 两侧语言按钮选择说话方向，停顿后收句；再次点当前按钮可主动收句。
- 系统语音识别实时显示原文，DeepSeek 官方文字接口流式显示译文。
- 系统语音播报，可开关；播放时停止录音，避免自身播报被识别。
- 可连续监听当前方向，换人时点另一侧；停止、退后台、来电中断或音频设备断开时停止当前任务。
- 文字输入和译文重播；显示 API 首字与全文耗时。此耗时不含语音识别和播放启动。
- API 密钥只存本机 Keychain，对话只保存在内存，最多 100 条；不记录原始音频。
- 识别提示词、0.5–1.6 秒停顿收句；等待识别最终修订，最多额外 0.6 秒。
- iOS 18+ 接入 Apple Translation 的语言包准备与本地文字翻译；不支持时明确报错，不偷偷换云端。
- 单独开关“只使用设备端语音识别”，检查设备与所选语言的离线识别能力。

语言列表包含中文、英语、希伯来语、日语等 17 个常用语种。列表代表可选配置，**不等于所有设备都能识别或播报这些语言**，也不等于 Apple 提供对应离线翻译包。文字翻译能力、ASR 能力、TTS 能力必须分别确认。

**当前不实现截图中的双语语音自动检测、双方同时说话、长句增量语音播报，也未接入第三方离线 ASR/翻译模型。** 第一版是按方向使用的对话翻译；自动双语识别是下一阶段功能。不能拿文字语言检测替代可靠的音频语言识别。

## 在 macOS 构建和安装

需要安装 Xcode（含 iOS 18+ SDK，建议最新稳定版）、Command Line Tools、Homebrew。App 最低系统 iOS 15，iOS 14 巨魔设备不能安装本版本。

```bash
brew install xcodegen
cd conversation-translator
xcodegen generate
open ConversationTranslator.xcodeproj
```

普通 iPhone：在 Xcode 的 Signing & Capabilities 选择自己的 Apple ID / Team，连接 iPhone，选择设备并运行；按系统提示信任开发者，iOS 16+ 可能需要启用开发者模式。免费 Apple ID 的开发签名通常约 7 天，需重新签名安装；无需申请 App Store 上架。付费开发者账户可延长开发分发的便利性，费用依地区和 Apple 当前规则确定。IPA 本身不能免签直接装到普通 iPhone。

兼容的巨魔 iPhone：

```bash
./scripts/build-ipa.sh
```

生成 `dist/ConversationTranslator-unsigned.ipa`，通过已经安装的 TrollStore 导入。本项目不安装 TrollStore、不要求越狱，也不使用特殊权限；仍需授予麦克风/语音识别权限。**兼容版本、Keychain 保存、Speech 权限、弱链接 Translation 框架都需要在实际巨魔设备验证。**

也提供 `.github/workflows/ios.yml`：将本目录作为仓库根目录推送到自己的 GitHub 仓库后，可手动运行 workflow，在 macOS runner 上编译、执行 SSE 单元测试、生成可下载的 unsigned IPA。当前没有创建远程仓库或执行此流程；私有仓库 runner 可能消耗计费额度。

## 首次使用

1. 设置中填入自己的 DeepSeek 官方 API Key 并保存；不要提交到 GitHub，也不必把 Key 发到聊天中。
2. 选择双方语言，点击自己的语言按钮并允许录音/识别权限。
3. 停顿后出现译文并自动播报；对方点击另一侧说话。文字输入方向可点击下方方向说明切换。
4. 下载系统声音：iPhone 设置 → 辅助功能 → 朗读内容/朗读与语音（名称因系统而异）→ 声音。选择相应语言并下载；App 使用系统实际可用的 voice。
5. 离线：iOS 18+ 开启系统离线翻译，准备语言包，同时开启设备端语音识别，下载所需声音，再断网检查三个环节。在线 Apple ASR 可能上传音频；仅开启离线文字翻译并不能保证全链路离线。

App 的离线模型由 Apple 管理，不提供任意文件形式的自定义翻译包下载。受 Apple 支持语言、系统储存空间、设备能力限制。不保证希伯来语离线翻译可用。

## 测量官方 API

Python 探针无额外依赖，只在提供环境变量后联网请求。默认发送一条中文问路句子，会产生少量 API 费用。

```bash
read -s -p 'DeepSeek API Key: ' DEEPSEEK_API_KEY
export DEEPSEEK_API_KEY
python3 scripts/probe_deepseek.py --source Chinese --target English
unset DEEPSEEK_API_KEY
```

至少在实际手机网络和不同时间测 20 次，记录中位数和 P95；不要用单次最好成绩承诺速度。探针只测文字翻译，完整对话仍需真机测录音结束到第一段译音的时间。

## 工程说明

`App/SpeechService.swift` 管理麦克风、识别、收句和播报；`DeepSeekClient.swift` 请求官方固定 HTTPS 地址并解析 SSE；`ConversationModel.swift` 管理状态与取消；`OfflineBridge.swift` 在 iOS 18+ 使用 Translation；`ConversationView.swift` 是简洁界面与设置。

工程使用系统框架，无第三方运行时依赖。调用 `deepseek-chat`，流式输出，不使用推理模型。DeepSeek 服务端模型版本与性能可能变化；需要实测。`max_tokens=1024`，主要面向短句；截断、认证错误、限流、连接中断会提示失败，未完成译文不会自动播报。

请先阅读 [方案与路线](docs/PLAN.md) 和 [真机验收清单](docs/ACCEPTANCE.md)。
