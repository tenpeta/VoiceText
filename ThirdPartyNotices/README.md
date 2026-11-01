# 第三方组件与资源

VoiceText 前端独立实现，不包含鼠须管的前端、图标或皮肤代码。

`Scripts/bootstrap.py` 从固定版本下载依赖和许可证，生成到 `upstream/`，构建时随应用一起复制。资源清单中记录源 URL 与 SHA-256。

许可证目录与词库使用 Xcode 标准资源阶段复制并参与签名依赖；GPLv3 与 LGPLv3 正文一并保留。不要在应用签名后修改包内的资源或声明文件。

| 组件 | 来源 / 版本 | 许可证 |
|---|---|---|
| librime | rime/librime 1.17.0 / 33e7814 | BSD-3-Clause |
| glog、LevelDB、marisa-trie、yaml-cpp、OpenCC、darts-clone | 官方 librime 发布包内的静态依赖；对应源码版本见 bootstrap 脚本 | 随包提供各项原始许可证 |
| librime-lua / Lua | hchunhui/librime-lua ec52e48 / Lua 5.4.8 | BSD-3-Clause / MIT（原文保存在 Lua 头文件末尾） |
| 白霜中文词库（8105/base/ext/others） | gaboolic/rime-frost / af22941 | GPL-3.0，保留各词典文件的来源声明 |
| melt_eng 英文词库（en/en_ext） | iDvel/rime-ice / 99662ba | GPL-3.0，保留各词典文件的来源声明 |
| 八股文语料 | rime/rime-essay / 054920d | 以随包原始 LICENSE 为准 |
| zlib、SQLite、Apple 系统框架 | 操作系统提供，动态链接 | 对应系统与上游许可 |

仅捆绑 librime-lua 用于有界候选排序，不捆绑 octagram、predict 插件。基础词典源文件与 essay.txt 随包保留，可在用户 Rime 目录中覆盖并由引擎重新部署；修改资源时必须保留上游许可与来源。

发布审查还应核对实际构建产物及上游静态依赖。开发构建使用 ad hoc 签名，不代表已经获得 Developer ID 公证。
