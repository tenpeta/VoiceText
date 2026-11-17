# 第三方组件与资源

VoiceText 前端独立实现，不包含鼠须管的前端、图标或皮肤代码。

`Scripts/bootstrap.py` 从固定版本下载依赖和许可证，生成到 `upstream/`，构建时随应用一起复制。资源清单中记录源 URL 与 SHA-256。

许可证目录与词库使用 Xcode 标准资源阶段复制并参与签名依赖；GPLv3 与 LGPLv3 正文一并保留。不要在应用签名后修改包内的资源或声明文件。

| 组件 | 来源 / 版本 | 许可证 |
|---|---|---|
| librime | rime/librime 1.17.0 / 33e7814 | BSD-3-Clause |
| glog、LevelDB、marisa-trie、yaml-cpp、OpenCC、darts-clone | 官方 librime 发布包内的静态依赖；对应源码版本见 bootstrap 脚本 | 随包提供各项原始许可证 |
| librime-lua / Lua | hchunhui/librime-lua ec52e48 / Lua 5.4.8 | BSD-3-Clause / MIT（原文保存在 Lua 头文件末尾） |
| librime-octagram | lotem/librime-octagram dfcc151，来自同一 librime 1.17.0 发布包 | GPL-3.0 |
| 白霜中文词库（8105/base/ext/others） | gaboolic/rime-frost / 4b190b8 | GPL-3.0，保留各词典文件的来源声明 |
| 白霜全拼规则、英文降权脚本与名单、`zh-moqi.gram` | gaboolic/rime-frost / af22941caec0fb7c052893e1bf439b79a94e5fb2 | 随包保留白霜仓库的 GPL-3.0 原文，模型未附单独许可 |
| melt_eng 英文词库（en/en_ext）和 emoji 词表 | iDvel/rime-ice / 927e1cf | GPL-3.0，保留各词典文件的来源声明 |
| 八股文语料 | rime/rime-essay / 054920d | 以随包原始 LICENSE 为准 |
| zlib、SQLite、Apple 系统框架 | 操作系统提供，动态链接 | 对应系统与上游许可 |

拼写规则、组句设置及降权名单摘自白霜的全拼方案。原样下载英文降权脚本和白霜随附的 `zh-moqi.gram`，并校验 SHA-256。模型为 7,339,052 字节，最早由白霜提交 `d57f35b` 加入。白霜 README 指向墨奇的模型生成项目，所用文件以白霜随附版本为准。[全拼方案](https://github.com/gaboolic/rime-frost/blob/af22941caec0fb7c052893e1bf439b79a94e5fb2/rime_frost.schema.yaml) · [模型提交](https://github.com/gaboolic/rime-frost/commit/d57f35b37b95a885ce36ef58fd539a7fa98b89f1) · [模型生成项目](https://github.com/gaboolic/rime-build-grammar)

应用捆绑 librime-lua 执行英文降权脚本，捆绑 librime-octagram 加载组句模型。[librime-octagram 源码与许可](https://github.com/lotem/librime-octagram/tree/dfcc151)

基础词典源文件与 essay.txt 随包保留，可在用户 Rime 目录中覆盖并由引擎重新部署。修改资源时必须保留上游许可与来源。

发布审查还应核对实际构建产物及上游静态依赖。开发构建使用 ad hoc 签名，不代表已经获得 Developer ID 公证。
