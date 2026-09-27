# 豆包语音输入自动复制到剪贴板（macOS）

按住**右 Option** 用豆包输入法说话，松开后，本轮输入的文字会写入 **macOS 系统剪贴板**。文字仍会正常留在输入框里；如果安装了 Maccy，它也会把这次复制保存到历史记录。Maccy 不是必需的。

## 安装

需要 [Hammerspoon](https://www.hammerspoon.org/)（放在 `/Applications`）、豆包输入法，以及 Xcode Command Line Tools。尚未安装命令行工具时，先运行 `xcode-select --install`。豆包的语音快捷键需设为**长按右 Option、松开结束**。

```bash
git clone https://github.com/eshoyuan/doubao-voice-clipboard.git
cd doubao-voice-clipboard
bash install.sh
```

安装脚本会编译按键桥接程序、将 Lua 脚本接入 Hammerspoon，并设置登录后自动启动。它会保留已有的 Hammerspoon 配置，并在第一次修改时备份 `init.lua`。

然后在 **系统设置 → 隐私与安全性** 中允许：

1. **辅助功能**：开启 Hammerspoon。
2. **输入监控**：点击 `+`，添加 `~/.hammerspoon/doubao-hid-bridge` 并开启。文件夹是隐藏的，可在文件选择器按 `⌘⇧G`，粘贴这个路径。

授权输入监控后，运行：

```bash
launchctl kickstart -k gui/$(id -u)/local.doubao.voiceclipboard.bridge
```

如果安装脚本提示 Hammerspoon 配置未加载，请从 Hammerspoon 菜单选择 **Reload Config**。测试时，在一个普通输入框里按住右 Option 说一句话，松开后试着粘贴，或查看 Maccy。

## 说明

- 每次成功捕获后，转写会**替换系统剪贴板的当前内容**；Maccy 只是记录这个变化。
- 工具只读取当前输入框在本轮语音前后的变化。密码框和无法通过 macOS 辅助功能读取文字的输入框会跳过，因此不能保证每个应用都适用。
- 桥接程序只处理右 Option 的按下与松开；转写内容不会写入日志。macOS 的“输入监控”权限本身允许程序监测键盘事件，请按需审阅源码。

## 排查

查看 Hammerspoon 最近一次状态：

```bash
hs -c 'print(doubaoVoiceClipboard.lastStatus)'
```

若 `hs` 不在 `PATH`，可用 `/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs` 代替。若日志里出现 `Input Monitoring granted: false`，在系统设置中删除旧的同名权限记录，重新添加当前安装路径，再执行上面的 `launchctl kickstart` 命令。

更新项目时运行 `git pull && bash install.sh`。如果桥接源码更新，macOS 可能要求重新授予输入监控权限。
