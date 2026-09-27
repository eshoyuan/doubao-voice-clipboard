#!/bin/bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
hs_app="/Applications/Hammerspoon.app"
agent_label="local.doubao.voiceclipboard.bridge"
trigger=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)
      if [[ $# -lt 2 || -z "$2" ]]; then echo "--trigger needs a shortcut" >&2; exit 2; fi
      trigger="$2"
      shift 2
      ;;
    --help)
      echo "Usage: bash install.sh [--trigger right-option|fn|control+space|keycode:NN]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$hs_app" ]]; then
  echo "Install Hammerspoon in /Applications first." >&2
  exit 1
fi
for tool_name in swiftc python3 launchctl; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "Missing $tool_name. Install Xcode Command Line Tools with: xcode-select --install" >&2
    exit 1
  fi
done

hs_cli="$(command -v hs || true)"
if [[ -z "$hs_cli" ]]; then
  hs_cli="$hs_app/Contents/Frameworks/hs/hs"
fi
if [[ ! -x "$hs_cli" ]]; then
  echo "Could not find the Hammerspoon hs command-line tool." >&2
  exit 1
fi

hs_dir="$(python3 -c 'from pathlib import Path; print(Path.home() / ".hammerspoon")')"
agent_file="$(python3 -c 'from pathlib import Path; print(Path.home() / "Library/LaunchAgents/local.doubao.voiceclipboard.bridge.plist")')"
if [[ -z "$trigger" ]]; then
  trigger="$(python3 - "$agent_file" <<'PY'
from pathlib import Path
import plistlib
import sys
path = Path(sys.argv[1])
if path.exists():
    args = plistlib.loads(path.read_bytes()).get("ProgramArguments", [])
    if "--trigger" in args and args.index("--trigger") + 1 < len(args):
        print(args[args.index("--trigger") + 1])
        raise SystemExit
print("right-option")
PY
)"
fi
mkdir -p "$hs_dir"
history_dir="$(python3 -c 'from pathlib import Path; print(Path.home() / "Library/Application Support/DoubaoVoiceClipboard")')"
mkdir -p "$history_dir"
chmod 700 "$history_dir"
touch "$history_dir/history.txt"
chmod 600 "$history_dir/history.txt"
cp "$repo_dir/DoubaoVoiceClipboard.lua" "$hs_dir/DoubaoVoiceClipboard.lua"

bridge_hash="$(shasum -a 256 "$repo_dir/DoubaoHIDBridge.swift" | cut -d ' ' -f 1)"
hash_file="$hs_dir/.doubao-bridge-source.sha256"
if [[ ! -x "$hs_dir/doubao-hid-bridge" || ! -f "$hash_file" || "$(cat "$hash_file")" != "$bridge_hash" ]]; then
  swiftc "$repo_dir/DoubaoHIDBridge.swift" -o "$hs_dir/.doubao-hid-bridge.new"
  if ! "$hs_dir/.doubao-hid-bridge.new" --validate-trigger "$trigger"; then
    rm -f "$hs_dir/.doubao-hid-bridge.new"
    exit 2
  fi
  mv -f "$hs_dir/.doubao-hid-bridge.new" "$hs_dir/doubao-hid-bridge"
  chmod 755 "$hs_dir/doubao-hid-bridge"
  printf '%s\n' "$bridge_hash" > "$hash_file"
  echo "Bridge built. macOS may require Input Monitoring permission again after an update."
fi
"$hs_dir/doubao-hid-bridge" --validate-trigger "$trigger"

python3 - "$hs_dir" "$hs_cli" "$trigger" <<'PY'
from pathlib import Path
import plistlib
import shutil
import sys

hs_dir = Path(sys.argv[1])
hs_cli = sys.argv[2]
trigger = sys.argv[3]
init_file = hs_dir / "init.lua"
old = init_file.read_text() if init_file.exists() else ""
start = "-- doubao-voice-clipboard:start"
if start not in old and "-- Doubao voice clipboard support" not in old:
    if init_file.exists():
        backup = hs_dir / "init.lua.before-doubao-voice-clipboard"
        if not backup.exists():
            shutil.copy2(init_file, backup)
    block = (
        "\n\n" + start + "\n"
        'require("hs.ipc")\n'
        'doubaoVoiceClipboard = dofile(hs.configdir .. "/DoubaoVoiceClipboard.lua")\n'
        "-- doubao-voice-clipboard:end\n"
    )
    init_file.write_text(old.rstrip("\n") + block)

agent_file = Path.home() / "Library/LaunchAgents/local.doubao.voiceclipboard.bridge.plist"
agent_file.parent.mkdir(parents=True, exist_ok=True)
agent = {
    "Label": "local.doubao.voiceclipboard.bridge",
    "ProgramArguments": [str(hs_dir / "doubao-hid-bridge"), hs_cli, "--trigger", trigger],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ThrottleInterval": 10,
    "StandardErrorPath": str(Path.home() / "Library/Logs/DoubaoVoiceClipboard.log"),
}
with agent_file.open("wb") as stream:
    plistlib.dump(agent, stream)
PY

open -a Hammerspoon
"$hs_cli" -c 'hs.reload()' >/dev/null 2>&1 || true
hs_ready=false
for _ in 1 2 3; do
  if "$hs_cli" -c 'print(doubaoVoiceClipboard and "ready" or "missing")' 2>/dev/null | grep -q ready; then
    hs_ready=true
    break
  fi
  sleep 1
done
if [[ "$hs_ready" == true ]]; then
  "$hs_cli" -c 'hs.autoLaunch(true)' >/dev/null 2>&1 || true
  echo "Hammerspoon configuration loaded."
else
  echo "In Hammerspoon, choose Reload Config once."
fi

launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$(python3 -c 'from pathlib import Path; print(Path.home() / "Library/LaunchAgents/local.doubao.voiceclipboard.bridge.plist")')"

echo "Installed. Give the bridge Input Monitoring permission, then restart it with:"
echo "launchctl kickstart -k gui/$(id -u)/$agent_label"
echo "Voice trigger: $trigger"
echo "Voice history: $history_dir/history.txt"
