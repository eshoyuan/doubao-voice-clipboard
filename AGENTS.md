# Agent installation guide

This repository is a macOS helper for Doubao IME press-and-hold voice input. It copies each readable final transcription to the system clipboard and appends the local timestamp plus text to `~/Library/Application Support/DoubaoVoiceClipboard/history.txt`.

When a user asks you to install or update it, do the installation yourself. Treat the voice shortcut as a setting to discover and configure; **right Option is only the fallback**.

## Install

1. Inspect the current Mac first: Doubao IME voice shortcut, Hammerspoon installation and configuration, existing LaunchAgent, and the history file. Prefer the current Doubao press-and-hold shortcut. If it cannot be read from settings or inferred from the conversation, ask the user which shortcut starts and ends dictation. Do not silently change Doubao's shortcut.
2. Obtain this repository and read the scripts before running them. Install Hammerspoon in `/Applications` and Xcode Command Line Tools if missing, using the available package manager or standard installer. Keep existing Hammerspoon configuration.
3. Run `bash install.sh --trigger 'SHORTCUT'` from this repository. Supported named base keys: `left-command`, `right-command`, `left-shift`, `right-shift`, `left-option`, `right-option`, `left-control`, `right-control`, `fn`, `space`, `tab`, `return`, `escape`, and `f1`–`f12`. A physical key code can be written as `keycode:NN` (0–127, except caps lock). Put required modifiers before the base key, such as `control+space` or `right-command+shift+space`. Only press-and-hold shortcuts are supported. If no `--trigger` is supplied, the installer preserves an existing configured trigger; on a new installation it uses `right-option`.
4. Handle macOS permissions: Hammerspoon needs Accessibility; `~/.hammerspoon/doubao-hid-bridge` needs Input Monitoring. Open the relevant System Settings screens and guide the user through any required macOS consent. Never bypass those prompts. After granting Input Monitoring, restart the bridge with `launchctl kickstart -k gui/$(id -u)/local.doubao.voiceclipboard.bridge`.
5. Check that Hammerspoon loaded `doubaoVoiceClipboard`, the LaunchAgent is running with the chosen trigger, and the bridge log does not report `Input Monitoring granted: false`. Ask the user for one short dictation using their normal shortcut. Confirm that pasting works and that the history file gained one timestamped entry. Verify size, timestamp, or entry count without printing the transcription into logs or chat.

## Update and troubleshooting

- Run `git pull` and `bash install.sh` to update while preserving the installed trigger. Use `--trigger` only to choose a different one. An update never truncates the history file.
- If the bridge binary was rebuilt, macOS may require Input Monitoring permission again. Check the permission and restore it through System Settings if needed.
- The updated bridge receives global key down/up events to recognize configurable shortcuts. It forwards only the selected shortcut's edges, but macOS Input Monitoring grants broader keyboard visibility. Explain this when requesting renewed permission.
- Hammerspoon status: `hs -c 'print(doubaoVoiceClipboard.lastStatus)'`. The CLI also exists at `/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs`.
- Check the LaunchAgent with `launchctl print gui/$(id -u)/local.doubao.voiceclipboard.bridge`. The bridge log is `~/Library/Logs/DoubaoVoiceClipboard.log`.
- Do not add the history file, private transcripts, or permission diagnostics containing personal content to Git. Do not upload the history file to another service.
- If an input field is inaccessible through macOS Accessibility, report that limitation. The helper intentionally skips secure fields and unreadable input.
