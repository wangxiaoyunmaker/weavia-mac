# 源码版本索引

main 指向 v0.2.8-build10-startup-recovery，这是独立已测候选，不是对当前运行应用的更换。版本号附加 startup-recovery 以区别后来仍在开发的快捷键候选。源码与用户数据完全分开。

| 标签或分支 | 状态 |
|---|---|
| v0.2.5-build6 | 历史整合源码；主目录现有app另为旧0.2.3，不用它代表本快照 |
| v0.2.6-build8 | 历史单行项目头与首次图层恢复版本 |
| v0.2.7-build9 | 历史整合候选；撤回、选区、图片/PDF/Figma卡片；存在已知旧pending覆盖新快照风险，后续startup-recovery修复 |
| v0.2.8-build10-startup-recovery | 当前最新完整已测候选：启动恢复选择与连线缩放修复；不代表用户正在运行的版本 |
| candidate/smart-tags | 独立智能标签功能候选，不称完整整合版 |
| candidate/canvas-history | 独立历史/关系候选，内部build7；不是正式0.2.6-build8 |
| candidate/selection-sync | 独立框选/套索同步候选 |
| candidate/media-cards | 独立图片/PDF/Figma卡片候选 |
| archive/original-native | 原生Mouse Companion原型源码归档，不推定正式版本号 |

0.2.1、0.2.3、0.2.4未发现对应完整源码快照，只有部分应用包；不编造源码标签，也不上传二进制。shortcut-focus工作目录在本次冻结时仍开发中，未收入任何稳定/整合标签。各完整版本的app静态资源与源码已核对，0.2.7/0.2.8的二进制哈希也与既有打包记录一致，但这些应用包和原始报告不上传。

本次只读复验：八个Mac快照的JS/MJS、shell、Python及JSON语法检查通过；0.2.7八组、0.2.8十组纯Node测试通过。原始原型JS/MJS、Python、shell语法通过。原生UI/实时模型/权限/输入法/多屏及实际文件选择器等不属于源码归档验证。后续在发布clone的构建结果另行记录。

发布clone最终复验：0.2.8 startup-recovery全部画布JavaScript语法、10组纯Node测试与swift build -c release -j 2通过。编译仅在独立源码clone进行，未启动AppDelegate、读取钥匙串、操作运行应用或用户项目；.build与日志不上传。
