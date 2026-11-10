# WEAVIA · Mac

源码快照：v0.2.5-build6

状态：历史整合源码；主目录现有app另为旧0.2.3，不用它代表本快照。

这是私有源码备份，不会启动、安装或替换当前应用。默认主分支为最新完整startup-recovery候选；其他已测版本与功能分支见 VERSION_STATUS.md。

## 构建与安全复验

需要macOS 13+及官方Xcode命令行工具。Package.swift不含第三方依赖或构建插件。

- 仅编译：swift build -c release -j 2（不会启动AppDelegate）。
- 完整应用打包：若本快照有build_app.sh，可使用zsh build_app.sh；不会自动打开生成应用。
- 纯Node回归：逐一运行Tests/*Tests.js；语法检查Sources/MouseCompanion/CuppaCanvas/*.js。
- 不要把BrowserSessionCheck.mjs、live/UI脚本或swift run当成无副作用的构建检查；这些步骤需要另行审查和适当环境。

## 功能与边界

Mac工作台复用原鼠标伙伴和本地空间画布，材料、项目快照与会话留在本机。图片/PDF/Figma引用、撤回、选区及智能标签支持程度随版本不同。真实模型/账户、实际输入法、多显示器、跨应用屏幕采集与真实文件选择器没有因源码归档而获得新验收。历史撤回有界且不跨重启，附件不自动清理。原型分支不等同于后续完整工作台。

## 数据和资源

源码不携带用户项目、导入素材、会话、密钥、截图日志、原始验收记录、app、build或备份。Tests只保留代码，使用者应先确认测试性质。打包用品牌原图是产品图标；网页内置示例资源与既有Harmony产品基线一致，非实际用户项目。保留来源说明；私有源码备份不新增开源或图片许可。运行应用所需权限仍由用户在系统设置自行决定。
