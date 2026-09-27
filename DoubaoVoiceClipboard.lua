-- Copy the text inserted during one right-Option dictation to the macOS clipboard.
-- Load with: doubaoVoiceClipboard = dofile("/absolute/path/DoubaoVoiceClipboard.lua")
-- Requires Hammerspoon Accessibility permission. The HID bridge needs Input Monitoring.

local M = {}
local active
local timer

M.lastStatus = "not started"
M.history = {}
M.archivePath = os.getenv("HOME") .. "/Library/Application Support/DoubaoVoiceClipboard/history.txt"

local function status(message)
    M.lastStatus = message
    M.history[#M.history + 1] = {at = hs.timer.secondsSinceEpoch(), message = message}
    if #M.history > 30 then table.remove(M.history, 1) end
    print("[DoubaoVoiceClipboard] " .. message)
end

local function stopTimer()
    if timer then timer:stop(); timer = nil end
end

local function cancel(reason)
    stopTimer()
    active = nil
    if reason then status(reason) end
end

local function saveTranscript(text)
    -- The installer creates this file with owner-only permissions. Do not
    -- silently create a new file with Lua's default, possibly public, mode.
    if hs.fs.attributes(M.archivePath, "mode") ~= "file" then
        return false, "history file is missing"
    end
    local file, openError = io.open(M.archivePath, "a")
    if not file then return false, openError end
    local written, writeError = file:write(os.date("%Y-%m-%d %H:%M:%S %z"), "\n", text, "\n\n")
    if not written then
        file:close()
        return false, writeError
    end
    local flushed, flushError = file:flush()
    local closed, closeError = file:close()
    if not flushed then return false, flushError end
    if not closed then return false, closeError end
    return true
end

local function focused()
    local app = hs.application.frontmostApplication()
    if not app then return nil end
    local element = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
    if not element then return nil end
    local role = element:attributeValue("AXRole")
    local subrole = element:attributeValue("AXSubrole")
    if subrole == "AXSecureTextField" then return nil end
    if role ~= "AXTextField" and role ~= "AXTextArea" and role ~= "AXComboBox"
       and role ~= "AXGroup" and role ~= "AXWebArea" then return nil end
    local value = element:attributeValue("AXValue")
    if type(value) ~= "string" or #value > 200000 then return nil end
    return { app = app, pid = app:pid(), element = element, value = value }
end

local function codepoints(s)
    local result = {}
    for _, cp in utf8.codes(s) do result[#result + 1] = utf8.char(cp) end
    return result
end

-- A single changed span is the closest observable approximation of the IME insertion.
function M.extract(before, after)
    if type(before) ~= "string" or type(after) ~= "string" or before == after then return nil end
    local ok, result = pcall(function()
        local a, b = codepoints(before), codepoints(after)
        local prefix = 0
        while prefix < math.min(#a, #b) and a[prefix + 1] == b[prefix + 1] do
            prefix = prefix + 1
        end
        local suffix = 0
        while suffix < math.min(#a - prefix, #b - prefix)
          and a[#a - suffix] == b[#b - suffix] do
            suffix = suffix + 1
        end
        local inserted = table.concat(b, "", prefix + 1, #b - suffix)
        if inserted == "" or not inserted:match("%S") then return nil end
        return inserted
    end)
    return ok and result or nil
end

local function poll()
    local c = active
    if not c then return end
    local now = hs.timer.secondsSinceEpoch()
    local value = c.element:attributeValue("AXValue")
    if type(value) == "string" and #value <= 200000 and value ~= c.observed then
        c.observed = value
        c.changedAt = now
        local candidate = M.extract(c.before, value)
        if candidate then c.lastInserted = candidate end
    end
    if not c.released then return end
    if now > c.deadline then cancel("no readable final text") return end
    if hs.pasteboard.changeCount() ~= c.clipboardCount then
        cancel("clipboard changed during dictation; skipped") return
    end
    local inserted = M.extract(c.before, c.observed)
    -- If the user sends immediately, the field can clear before the final poll.
    if not inserted and c.lastInserted then inserted = c.lastInserted end
    if not inserted then return end
    if M.extract(c.before, c.observed) and c.changedAt and now - c.changedAt < 0.5 then return end
    if hs.pasteboard.setContents(inserted) then
        local saved, saveError = saveTranscript(inserted)
        if saved then
            status("copied and saved " .. tostring(utf8.len(inserted) or #inserted) .. " characters")
        else
            status("copied but could not save history: " .. tostring(saveError))
        end
    else
        status("failed to write clipboard")
    end
    cancel()
end

local function begin()
    cancel()
    local before = focused()
    if not before then status("focused field is unreadable; skipped") return end
    active = {
        before = before.value, observed = before.value,
        element = before.element, pid = before.pid,
        pressedAt = hs.timer.secondsSinceEpoch(),
    }
    timer = hs.timer.doEvery(0.1, poll)
    status("capturing")
end

local function finish()
    local c = active
    if not c then return end
    if hs.timer.secondsSinceEpoch() - c.pressedAt < 0.2 then
        cancel("short right-Option press; skipped") return
    end
    c.released = true
    c.clipboardCount = hs.pasteboard.changeCount()
    c.deadline = hs.timer.secondsSinceEpoch() + 8
    poll()
end

function M.start()
    status("running")
    return true
end

function M.stop()
    cancel()
    status("stopped")
end

-- Called by the HID bridge.
function M.beginCycle() begin() end
function M.endCycle() finish() end

M.start()
return M
