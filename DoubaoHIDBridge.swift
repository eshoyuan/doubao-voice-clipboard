import AppKit
import ApplicationServices

// Hammerspoon's session event tap does not see the right-Option key consumed
// by Doubao. This HID-level, listen-only tap forwards only that key's edges.
private let hammerspoonCLI = CommandLine.arguments.dropFirst().first
    ?? "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"
private let queue = DispatchQueue(label: "doubao.voice.clipboard.events")
private let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
private var rightOptionIsDown = false
private var eventTap: CFMachPort?

fputs("Input Monitoring granted: \(CGPreflightListenEventAccess())\n", stderr)

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
    guard type == .flagsChanged,
          event.getIntegerValueField(.keyboardEventKeycode) == 61 else {
        return Unmanaged.passUnretained(event)
    }
    let pressed = event.flags.contains(.maskAlternate)
    if pressed != rightOptionIsDown {
        rightOptionIsDown = pressed
        forward(pressed ? "doubaoVoiceClipboard.beginCycle()" : "doubaoVoiceClipboard.endCycle()")
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
