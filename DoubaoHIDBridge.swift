import AppKit
import ApplicationServices

// A listen-only HID tap sees shortcuts that Doubao consumes before Hammerspoon.
// The trigger must match Doubao's press-and-hold voice shortcut.
private struct Trigger {
    let keyCode: Int64
    let keyFlag: CGEventFlags?
    let requiredFlags: CGEventFlags

    init?(_ specification: String) {
        let parts = specification.lowercased()
            .split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains("") else { return nil }

        var required: CGEventFlags = []
        for name in parts.dropLast() {
            guard let flag = Self.modifierFlag(name) else { return nil }
            required.formUnion(flag)
        }

        let last = parts[parts.count - 1]
        let namedKeys: [String: Int64] = [
            "left-command": 55, "right-command": 54,
            "left-shift": 56, "right-shift": 60,
            "left-option": 58, "right-option": 61,
            "left-control": 59, "right-control": 62,
            "fn": 63, "space": 49, "tab": 48,
            "return": 36, "escape": 53,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        let code = namedKeys[last] ?? (last.hasPrefix("keycode:")
            ? Int64(last.dropFirst("keycode:".count)) : nil)
        guard let code, (0...127).contains(code), code != 57 else { return nil }

        keyCode = code
        keyFlag = Self.keyFlag(code)
        requiredFlags = required
    }

    private static func modifierFlag(_ name: String) -> CGEventFlags? {
        switch name {
        case "command": return .maskCommand
        case "shift": return .maskShift
        case "option": return .maskAlternate
        case "control": return .maskControl
        case "fn": return .maskSecondaryFn
        case "left-command": return CGEventFlags(rawValue: 0x08)
        case "right-command": return CGEventFlags(rawValue: 0x10)
        case "left-shift": return CGEventFlags(rawValue: 0x02)
        case "right-shift": return CGEventFlags(rawValue: 0x04)
        case "left-option": return CGEventFlags(rawValue: 0x20)
        case "right-option": return CGEventFlags(rawValue: 0x40)
        case "left-control": return CGEventFlags(rawValue: 0x01)
        case "right-control": return CGEventFlags(rawValue: 0x2000)
        default: return nil
        }
    }

    private static func keyFlag(_ code: Int64) -> CGEventFlags? {
        switch code {
        case 55: return modifierFlag("left-command")
        case 54: return modifierFlag("right-command")
        case 56: return modifierFlag("left-shift")
        case 60: return modifierFlag("right-shift")
        case 58: return modifierFlag("left-option")
        case 61: return modifierFlag("right-option")
        case 59: return modifierFlag("left-control")
        case 62: return modifierFlag("right-control")
        case 63: return modifierFlag("fn")
        default: return nil
        }
    }

    func isHeld(in flags: CGEventFlags) -> Bool {
        guard let keyFlag else { return false }
        return flags.contains(keyFlag) && flags.contains(requiredFlags)
    }
}

private let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--validate-trigger" {
    if arguments.count == 2, Trigger(arguments[1]) != nil {
        exit(0)
    }
    fputs("Invalid trigger. Use a named key or keycode:0-127; caps lock is unsupported.\n", stderr)
    exit(2)
}

if !arguments.isEmpty && arguments.count != 1 &&
    !(arguments.count == 3 && arguments[1] == "--trigger") {
    fputs("Usage: doubao-hid-bridge [hammerspoon-cli] [--trigger shortcut]\n", stderr)
    exit(2)
}

private let hammerspoonCLI = arguments.first
    ?? "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"
private let triggerName = arguments.count == 3 ? arguments[2] : "right-option"
private let trigger = Trigger(triggerName)
if trigger == nil {
    fputs("Invalid trigger: \(triggerName)\n", stderr)
    exit(2)
}

private let queue = DispatchQueue(label: "doubao.voice.clipboard.events")
private let mask = CGEventMask(
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue)
)
private var triggerIsDown = false
private var eventTap: CFMachPort?

fputs("Input Monitoring granted: \(CGPreflightListenEventAccess()); trigger: \(triggerName)\n", stderr)

private func forward(_ command: String) {
    queue.async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hammerspoonCLI)
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                fputs("Hammerspoon command failed: \(process.terminationStatus)\n", stderr)
            }
        } catch {
            fputs("Could not contact Hammerspoon: \(error)\n", stderr)
        }
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard let trigger else { return Unmanaged.passUnretained(event) }

    if trigger.keyFlag != nil && type == .flagsChanged {
        let pressed = trigger.isHeld(in: event.flags)
        if pressed != triggerIsDown {
            triggerIsDown = pressed
            forward(pressed ? "doubaoVoiceClipboard.beginCycle()" : "doubaoVoiceClipboard.endCycle()")
        }
    } else if trigger.keyFlag == nil {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown && code == trigger.keyCode && !triggerIsDown &&
            event.flags.contains(trigger.requiredFlags) {
            triggerIsDown = true
            forward("doubaoVoiceClipboard.beginCycle()")
        } else if triggerIsDown &&
            ((type == .keyUp && code == trigger.keyCode) ||
             (type == .flagsChanged && !event.flags.contains(trigger.requiredFlags))) {
            triggerIsDown = false
            forward("doubaoVoiceClipboard.endCycle()")
        }
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                  place: .headInsertEventTap,
                                  options: .listenOnly,
                                  eventsOfInterest: mask,
                                  callback: callback,
                                  userInfo: nil) else {
    fputs("Could not start HID event tap\n", stderr)
    exit(1)
}
eventTap = tap

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
