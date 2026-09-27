# 豆包语音输入自动复制与存档（macOS）

豆包语音输入结束后，工具会把本轮文字复制到 **macOS 系统剪贴板**，并将本地时间和原文追加到 `~/Library/Application Support/DoubaoVoiceClipboard/history.txt`。输入框里的文字照常保留。

适用于豆包输入法的**按住说话、松开结束**快捷键。触发键可配置；右 Option 只是首次安装时的默认值。

## 让 Agent 安装

把下面这段话发给能操作你 Mac 的编程 Agent：

> 请在我的 Mac 上安装或更新 [doubao-voice-clipboard](https://github.com/eshoyuan/doubao-voice-clipboard)。先阅读仓库的 [AGENTS.md](AGENTS.md)，检查我在豆包输入法里实际使用的“按住说话”快捷键，并让桥接程序与它一致。保留我现有的 Hammerspoon 配置和语音记录，协助完成 macOS 权限设置，最后用一次真实语音输入验证复制和存档。

Agent 会使用 `install.sh --trigger '快捷键'` 配置触发键。可以是 `right-option`、`fn`、`control+space` 等；也支持 `keycode:NN` 指定物理键码。再次安装而不传 `--trigger` 时，会保留已配置的键。若 Agent 无法读取豆包设置，它会询问你当前使用的快捷键。

安装需要豆包输入法、[Hammerspoon](https://www.hammerspoon.org/) 和 Xcode Command Line Tools。macOS 的**辅助功能**与**输入监控**授权可能需要你在系统设置中点击允许，Agent 会引导完成。

## 语音记录

每条记录是本地时间、原文和一个空行：

```text
2026-09-27 09:30:00 -0700
这是一次语音输入。

```

工具只追加记录，不自动删除；更新程序也不会清空文件。文件和所在目录只对当前用户开放。要长期保留，请将文件纳入备份。安装之前的输入无法补录。

## 使用范围

工具通过 macOS 辅助功能读取当前输入框前后的变化。密码框及无法被读取的输入框会跳过，因此不能保证每个应用都适用。每次成功捕获后，文字会替换系统剪贴板的当前内容；如果写入记录文件失败，复制仍可用，错误会显示在 Hammerspoon 状态里。
