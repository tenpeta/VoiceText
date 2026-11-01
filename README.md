# VoiceText

原生 macOS 中文输入法与云端 ASR 听写。Swift / InputMethodKit / librime / AppKit，设置和语音历史按需使用 SwiftUI。

目前是可构建的开发版本，不是经过完整日用兼容性验收的正式发行版。

## 构建与测试

要求 Apple Silicon、macOS 14+、Xcode 15+，以及构建时可用的 Python 3。Python 仅用于下载依赖、生成工程和预编译资源，产品运行不需要 Python。无需 Homebrew 或第三方 Swift 包。

```sh
bash Scripts/build.sh
bash Scripts/test.sh
```

构建产物：`build/DerivedData/Build/Products/Release/VoiceText.app`。

`VoiceText.xcodeproj` 已提交，可直接打开。首次构建前运行 `python3 Scripts/bootstrap.py` 和 `python3 Scripts/prepare_resources.py`。增加源文件后运行 `python3 Scripts/generate_project.py` 更新工程。Xcode 共享 Scheme 默认启动设置窗口，方便验证 UI。

依赖固定为 librime 1.17.0，发布包下载前校验 SHA-256；资源固定到上游 commit。只打包 arm64 核心动态库、白霜精选词库、melt_eng 英文词库和简繁转换数据，仅带用于候选排序的 Lua 插件，不带预测等插件。预编译在构建阶段完成。

## 安装与更新

双击构建后的应用，在「输入」页选择安装，然后在系统设置 → 键盘 → 输入法中添加 VoiceText。

安装会向系统注册输入源；如系统设置已经打开，请重新打开后在「简体中文」中查找 VoiceText。注册成功不代表输入法已经启用或可以输入，请添加后切换并实际测试。

首次安装后如果系统设置中未出现 VoiceText，请重新登录 macOS 后再添加。

也可在完成构建后运行：

```sh
bash Scripts/install.sh
```

安装到 `~/Library/Input Methods/VoiceText.app`，不需要管理员权限。升级脚本先切换到 ABC、退出旧实例，暂存旧应用到 Application Support/VoiceText/Updates，再替换和注册；不删除用户词典或历史。应用内按钮仅处理首次安装和注册，已安装版本的替换请使用脚本。

不自动删除系统输入法，请保留 ABC 用于恢复。卸载时先切换 ABC、退出 VoiceText，再在系统设置移除输入源，将 `~/Library/Input Methods/VoiceText.app` 移到废纸篓。用户数据、本地密钥和旧 Keychain 条目默认保留；历史可在应用中清空。

## 中文输入

- 全拼、连续词句候选、用户词频学习、简繁转换、中英文与中英文标点。
- 中文使用固定版本白霜的 `8105/base/ext/others`，不加载大字表、腾讯大词库及细胞词库。个人学习词典使用 `dict_pinyin`，不再读取旧 `luna_pinyin` 学习词典。
- 原生带降权的拼写派生支持 `sh/ch/zh → hs/hc/hz` 和 `ia/ua/io/uo/ie/ue` 内部错序，以及 `ang/eng/ing/ong → agn/egn/ign/ogn` 等韵尾错序，例如 `xaingmu → 项目`、`kaui → 快`。
- 候选先统一繁转简，再按设置转为繁体并去重，避免旧学习记录与词库异体造成简繁混排。
- `melt_eng` 提供完整英文单词候选，关闭英文预测补全和英文用户词频学习，通过一个 Lua 过滤器对前 64 个候选排序：完整拼音匹配的中文优先，完整英文次之，简拼、纠错及其他结果保持原顺序。它根据原始拼音匹配判断，不做英文语义识别。
- 空格/数字选词、方向键、Page Up/Down 和 `-` / `=` 翻页、Esc 取消组合。横排时点击下拉箭头或按 ↓ 展开多行候选，方向键移动高亮，空格/回车确认，数字选择当前行；在顶部按 ↑ 或按 Esc 收起，继续输入自动回到单行。
- 单独轻按左侧或右侧 `Shift` 切换中英文；使用 Shift 输入大写或组合键时不会切换。
- 非激活 AppKit 候选窗，不抢文本焦点。支持横排/竖排、浅色/深色、字号、字体、圆角和间距。外观页保留主题、横竖排、字体和字号设置；候选窗口使用已确定的背景样式，保留基础实时预览，调试参数与桌面预览入口已移除。
- 设置由输入法菜单打开，关闭后释放 SwiftUI 视图。

## 语音输入

先在「语音」页选择 ASR 服务，填写**完整接口地址**和模型/资源 ID，填写并保存 API Key 到本机，并主动启用麦克风。不要把密钥提交到仓库或发到聊天中。豆包可先点「测试连接」检查 WebSocket 鉴权，不采集或发送录音。

默认单独轻按右侧 `Option` 开始，再按结束；Esc 取消；最长三分钟。可在设置中点击语音快捷键，再按下并松开一个键自动保存，左右 Option、Control 等分别识别。旧版组合快捷键会自动改为右 Option。快捷键仅通过本输入法的输入事件处理，未注册全局按键监听。

| 服务 | 默认接口 | 默认模型/资源 |
|---|---|---|
| 豆包 2.0 | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream` | `volc.seedasr.sauc.duration` |
| OpenAI ASR | `https://api.openai.com/v1/audio/transcriptions` | `gpt-transcribe`，按当前服务可用性调整 |
| 千问 ASR | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | `qwen3-asr-flash` |

豆包使用流式语音识别模型 **2.0** 的一句话接口，不是录音文件极速版。根据已开通资源填写资源 ID：`volc.seedasr.sauc.duration`（小时版）或 `volc.seedasr.sauc.concurrent`（并发版）。2.0 的旧版控制台使用 App ID 和 Access Token，新版控制台使用 API Key；可在设置中选择，现有配置和 API Key 保持不变。约 200 ms 一包 PCM，结束时发送最终包，只使用最终识别文本。网络发送有界缓冲，持续积压时明确终止，不静默丢帧、不无限缓存、不自动重发。

OpenAI 使用 multipart 文件上传；千问使用携带 Base64 音频的非流式 ASR 请求。千问的聊天格式只是一种传输格式，实际调用的是专用 ASR 模型。原生代码直接调用 API，不依赖服务商 SDK，也不上传到对象存储。

文本整理默认关闭；开启时配置独立的文本模型和密钥。只处理识别后的文字，失败使用原始转写。结果在处理完成后，一次性发送到当时的活动文本框；等待期间可以移动光标或切换应用。录音时仅在屏幕底部居中显示“录音中”胶囊提示，停止录音后立即隐藏；未识别到语音时静默结束。没有可靠活动 client、切换为其他输入法或正在本应用设置中时，弹出结果复制面板，保留到手动关闭；自动输入成功则不显示结果面板。

由于 InputMethodKit 不提供通用的宿主落字确认，界面仅显示「已发送」，不宣称宿主已成功接收。密码框、特殊编辑器和系统没有活动文本框的情况必须实机检查。

## 数据与权限

- 设置：UserDefaults，仅非敏感配置。
- 凭据：`~/Library/Application Support/VoiceText/Credentials/credentials.json`，目录权限 0700、文件权限 0600，仅当前账户可读写，不使用钥匙串加密；按 ASR 服务和文本整理分别保存。清空后保存可删除对应密钥。应用不再读写钥匙串。
- 词典：`~/Library/Application Support/VoiceText/Rime`。
- 历史：同目录上层的 `history.sqlite`，长期保留原文与最终文本，分页读取，可复制、单条删除和清空；数据库文件限制为当前用户读写。
- 音频：仅文件型 ASR 临时写入私有临时目录，完成、取消和失败时删除。豆包不累积整段音频。启动时清理本应用遗留临时文件。
- 不申请辅助功能、屏幕录制或输入监控权限，不记录键盘输入正文、API 请求正文或鉴权头。ASR 音频及可选整理文本发给用户配置的服务。

本地 ad hoc 构建不启用 Hardened Runtime，因为没有 Team ID 的签名无法通过随包动态库的 library validation。正式发行由下方脚本对动态库与应用使用同一 Developer ID 签名并启用 Hardened Runtime；没有添加禁用 library validation 的发行权限。

```sh
SIGNING_IDENTITY='Developer ID Application: …' NOTARY_PROFILE='your-profile' bash Scripts/package.sh
```

未提供上述配置时只生成开发测试 ZIP，不代表完成公证。不同签名版本的麦克风权限必须在最终安装路径复验。

## 验证与性能

`Scripts/test.sh` 运行 Swift 关键测试和真实 librime 一千次会话输入/上屏/释放测试，不需要 API Key，也不修改系统输入源。完整实机验收清单见 [Docs/Validation.md](Docs/Validation.md)。

键盘处理和候选绘制具有 Instruments signpost（subsystem `im.voicetext.inputmethod`，category `Input`），不包含正文。使用 Release 构建测量；不能把编译通过或协议单测当作真实云端识别、系统焦点或内存预算已经通过。

## 来源

- [Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [librime 1.17.0](https://github.com/rime/librime/releases/tag/1.17.0)
- [豆包一句话 ASR](https://docs.volcengine.com/docs/doubao-voice/unidirectional-streaming-automatic-speech-recognition-websocket?lang=zh)
- [豆包二进制协议](https://docs.volcengine.com/docs/doubao-voice/large-model-streaming-automatic-speech-recognition-api-1?lang=zh)
- [OpenAI 文件转写](https://developers.openai.com/api/docs/guides/speech-to-text)
- [千问 ASR](https://help.aliyun.com/zh/model-studio/recording-file-recognition-qwen)

许可证与来源见 [ThirdPartyNotices/README.md](ThirdPartyNotices/README.md)。
