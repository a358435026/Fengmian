# 可执行方案与性能边界

## 为什么先做原生 iPhone

原生应用能够使用 Apple 的录音会话、Speech、AVSpeechSynthesizer、Keychain，以及 iOS 18+ Translation。无需服务器托管 API 密钥；个人用的密钥在自己的设备直接请求官方接口。免费 Xcode 开发安装或兼容设备的 TrollStore 可以避免 App Store 上架。公众分发的产品应另设计服务器鉴权与限额，不能将开发者自己的密钥内置到包内。

Web/PWA 可做补充，但 iPhone 浏览器语音识别支持、后台录音与自动播放行为不同；不能以网页能录音等同于具备可靠的连续语音识别。因此本次交付原生 App 源码，不把网页冒充安装包。

TrollStore 官方 README 当前列出 14.0 beta 2–16.6.1、16.7 RC (20H18)、17.0；17.0.1+ 不在此漏洞支持范围。具体安装方法仍取决于设备。项目最低 iOS 15，若设备是 iOS 14，需要单独调整并验证兼容。

Apple TranslationSession 从 iOS 18 引入。故 TrollStore 路径通常不能使用 Apple 的原生离线文字翻译。旧系统要离线需接入第三方模型，不能靠下载 Apple 翻译包解决。

## 延迟怎么判断

停顿收句时间 + ASR 最终修订 + 网络/API 首字 + 剩余译文生成 + TTS 启动 = 停止说话到听到译音的时间。

本版自动收句默认 0.8 秒、可降低到 0.5 秒；最终识别修订最多再等 0.6 秒。仅收句步骤已使“停说到完整译音在零点几秒内”无法作为本版承诺。手动收句可减少停顿等待。API 首字快也不代表完整译音快。

在设备、语种、网络和句长未确定前，不提供预测的确定时延。“本地必然慢”和“官方 API 必然快”都不成立：小型量化本地模型没有网络开销，大型多语模型在旧设备上可能更慢，云端也受排队/网络影响。

先以短句和轮流说话验证正确率与时延，再根据测量决定是否引入更复杂的引擎。目标记录 API 首字、完整译文以及完整端到端 P50/P95；不能只追求最快一次。

进一步降低延迟可采用：

1. 音频 VAD 调整噪声底与收句阈值，减少无谓停顿。当前 RMS 固定阈值只是 MVP，嘈杂或轻声环境会受影响。
2. 流式 ASR 做稳定前缀确认，不对每个临时文字片段请求翻译，避免大量费用和错误重播。
3. 翻译第一完整分句后即可 TTS；不逐字播报，不重复播报被修订的译文。
4. 比较 DeepSeek 与专用机器翻译引擎的质量、P95、费用。用实测选择，不能保证大模型比专用翻译更快。

这些增量语音功能尚未实现。涉及语序后置的语言，翻译必须等待更多上下文；提前播报越激进，误译和返工风险越大。

## 识别率优化顺序

- 先确定两种语言、手机型号、系统；使用正确 locale，优先固定双语候选集合。
- 用安静环境、距离麦克风 20–40 厘米、双方轮流说话建立基线；再测试噪声和口音。
- 姓名、地名、专业术语加 contextualStrings；显示可检查的原文，不让 LLM 默默猜测错误音频。
- 对比系统识别、WhisperKit 与 sherpa-onnx 的错误率、P95、耗电、模型体积；不要一开始就下载大模型。
- 双语自动识别应基于多语 ASR 或音频语言检测，在所选两语间判定并设置低置信度的手动纠正。两个单语识别器的置信度不能直接当作可靠语言分类分数。
- 短数字、人名、两种语言混说、双方抢话都需要专门测试。本版两按钮明确方向，是稳定基线，尚不是截图中的全自动双语识别。

DeepSeek 的文字翻译无法修复没有听到、或被错误识别的声音；它可能把错误文字翻译得很流畅。应把识别准确率和翻译质量分开评分。

## 调研到的开源项目

于 2026-10-01 核实公开仓库元信息，未克隆、未进行全面代码或供应链审计。

| 项目 | 平台/用途 | 适合本项目的方式 |
| --- | --- | --- |
| [RTranslator](https://github.com/niedev/RTranslator) | Android 离线实时翻译，Apache-2.0 | 可参考流程和模型选择，不能直接产出 iOS IPA |
| [WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) | Apple Silicon 设备端语音 AI，MIT | 下一阶段候选离线多语 ASR，需要核实版本对旧 iOS/芯片的支持与模型性能 |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | iOS 等多平台 ASR/TTS/VAD，Apache-2.0 | 旧系统离线与流式识别候选，需分别核对模型语种及模型许可证 |

不直接 fork 一个不适合 iOS 的大应用。先保持小型独立项目，再选可替换的语音/翻译组件。任何模型下载前需检查模型许可证、大小、校验和与下载失败恢复；第三方仓库的许可证不自动覆盖所有模型。

## 三阶段执行

1. 当前源码：在 macOS 编译，巨魔/普通 iPhone 分别安装，填自己的 API Key，完成双向短句与播报验收，记录延迟；此阶段还未真机验证。
2. 根据目标语种接入多语音频自动检测，加入真正的 VAD、稳定分句与首句语音流水线；满足正确率要求后启用单麦克风全自动模式。
3. 旧系统离线：择一 ASR 模型，接入轻量专用翻译模型与系统 TTS，增加模型包下载/校验/删除。按设备和语言设支持清单，绝不承诺全语种或所有旧 iPhone 都实时。

## 依据

- [DeepSeek Chat Completion](https://api-docs.deepseek.com/api/create-chat-completion)：文字消息与 stream。
- [Apple TranslationSession](https://developer.apple.com/documentation/translation/translationsession)：原生翻译与系统版本。
- [Apple prepareTranslation](https://developer.apple.com/documentation/translation/translationsession/preparetranslation())：请求语言包下载许可。
- [TrollStore 官方 README](https://github.com/opa334/TrollStore)：支持版本。

设备的实际支持和官方后续变化，以编译和真机运行结果为准。
