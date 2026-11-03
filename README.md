# VoiceText

VoiceText 是一款原生 macOS 中文输入法，结合 Rime 拼音输入和云端语音听写。使用 Swift、InputMethodKit 和 AppKit 开发。

**项目目前处于开发阶段**，尚未完成日常使用的兼容性验收。安装后请保留系统自带的 ABC 输入法，以便遇到问题时切换。

## 功能

- **中文输入**：全拼、连续词句候选、词频学习、简繁转换和中英文标点；支持常见拼写错序纠正。
- **候选窗口**：支持横排或竖排、浅色或深色，以及字体、字号、圆角和间距设置；可展开多行候选。
- **中英文切换**：轻按左侧或右侧 Shift；用 Shift 输入大写或组合键时不会切换。
- **语音听写**：支持豆包、OpenAI 和千问 ASR，默认轻按右 Option 开始，再按一次结束，Esc 取消；快捷键可更改。
- **文本整理**：可选地用单独配置的文本模型整理转写结果，默认关闭；整理失败时保留原始转写。
- **语音历史**：在本机保存原始转写和最终文本，支持复制、删除和清空。

中文词库使用固定版本的白霜精选词库，英文候选使用 `melt_eng`。候选排序会优先显示完整拼音匹配的中文，其次是完整英文；不提供英文语义识别或预测。

## 环境要求

- Apple Silicon Mac，macOS 14 或更高版本
- Xcode 15 或更高版本
- Python 3 和构建时的网络连接，用于下载依赖和准备资源

不需要 Homebrew 或第三方 Swift 包；应用运行时不需要 Python。

## 构建和安装

在仓库目录运行：

```sh
bash Scripts/build.sh
```

首次构建会下载固定版本的 librime、词库及其他资源，并准备 Xcode 工程。librime 发布包会校验 SHA-256。构建完成后，应用位于：

```text
build/DerivedData/Build/Products/Release/VoiceText.app
```

双击应用，在「输入」页选择安装，然后在系统设置 → 键盘 → 输入法中添加 VoiceText。也可以在构建后运行 `bash Scripts/install.sh`。应用安装在 `~/Library/Input Methods/VoiceText.app`，无需管理员权限。

如果系统设置中没有出现 VoiceText，请关闭并重新打开系统设置；仍未出现时，重新登录 macOS 后再试。注册成功后仍需手动添加、切换并测试输入法。

更新已安装的版本请使用 `Scripts/install.sh`：脚本会先切换到 ABC，退出旧实例并备份旧应用，再替换和注册。用户词典和历史会保留。卸载时先切换到 ABC、退出 VoiceText，从系统设置中移除输入源，再将安装的应用移到废纸篓；用户数据和本地密钥默认保留。

也可直接打开已提交的 `VoiceText.xcodeproj`。首次在 Xcode 中构建前，先运行 `python3 Scripts/bootstrap.py` 和 `python3 Scripts/prepare_resources.py`。增加源文件后运行 `python3 Scripts/generate_project.py` 更新工程。

## 使用语音听写

在设置的「语音」页选择服务，填写完整接口地址、模型或资源 ID 和 API Key，保存后启用麦克风。使用云服务可能产生相应费用。豆包支持在录音前测试连接，该操作不采集或发送录音。

| 服务 | 默认接口 | 默认模型或资源 ID |
| --- | --- | --- |
| 豆包 2.0 | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream` | `volc.seedasr.sauc.duration` |
| OpenAI ASR | `https://api.openai.com/v1/audio/transcriptions` | `gpt-transcribe`，按服务实际可用性调整 |
| 千问 ASR | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | `qwen3-asr-flash` |

豆包使用一句话流式识别接口；可根据已开通的资源选择小时版或并发版资源 ID，也可在设置中选择新版 API Key 或旧版 App ID / Access Token 鉴权。OpenAI 和千问使用非流式请求。单次录音最长三分钟。

识别完成后，文本会发送到当时的活动文本框；等待期间可以移动光标或切换应用。如果没有可靠的活动输入目标、已切换到其他输入法或正在应用设置中，结果会显示在可复制的面板中。输入法无法通用地确认目标应用是否接收了文字，因此界面显示「已发送」。密码框和特殊编辑器等场景需要实际验证。

## 数据与隐私

- **音频与文本**：音频发送至用户配置的 ASR 服务；启用文本整理时，识别文本也会发送至配置的文本服务。文件型 ASR 的临时音频在完成、取消或失败后删除；应用启动时也会清理遗留临时文件。
- **密钥**：保存在 `~/Library/Application Support/VoiceText/Credentials/credentials.json`，目录权限为 0700、文件权限为 0600；不使用钥匙串加密。请勿将密钥提交到仓库。
- **词典和历史**：分别保存在 `~/Library/Application Support/VoiceText/Rime` 和同一目录下的 `history.sqlite`。历史长期保留，直到用户手动删除。
- **权限**：语音功能需要麦克风权限；应用不申请辅助功能、屏幕录制或输入监控权限，不记录键盘输入正文、API 请求正文或鉴权头。

## 测试与发布

```sh
bash Scripts/test.sh
```

测试包括 Swift 核心测试和真实 librime 的 1000 次会话测试，不需要 API Key，也不会修改系统输入源。自动测试通过不代表云端识别、目标应用焦点或日常使用兼容性已经完成验收。

本地构建使用 ad hoc 签名，适合开发测试。准备公开分发时，需要检查第三方许可证、使用 Developer ID 签名并完成公证，同时在最终安装路径重新验证麦克风权限：

```sh
SIGNING_IDENTITY='Developer ID Application: …' NOTARY_PROFILE='your-profile' bash Scripts/package.sh
```

未配置签名和公证时，打包脚本生成的 ZIP 仅供开发测试。

## 第三方组件与许可证

项目使用 librime、librime-lua、白霜和 `melt_eng` 等组件与资源。其来源、版本和许可证见 [ThirdPartyNotices/README.md](ThirdPartyNotices/README.md)。构建脚本会下载对应的上游资源及许可证；分发应用时应保留适用的许可声明。
