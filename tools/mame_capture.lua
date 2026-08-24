-- MAME autoboot script: at frame CAPTURE_FRAME dump the X Board video RAMs
-- and take a screenshot, then exit. Configure through environment variables
-- XB_FRAME (frame number) and XB_OUT (output directory).
local frame_target = tonumber(os.getenv("XB_FRAME") or "300")
local outdir = os.getenv("XB_OUT") or "."
local frame = 0
local done = false

local function dump(space, base, words, path)
    local f = io.open(path, "wb")
    for i = 0, words - 1 do
        local w = space:read_u16(base + i * 2)
        f:write(string.char(w & 0xff, (w >> 8) & 0xff))
    end
    f:close()
end

local test_mode = os.getenv("XB_TEST") == "1"
local test_field = nil
-- also press the switch from machine start, before the first frame
emu.register_start(function()
    if test_mode then
        local port = manager.machine.ioport.ports[":mainpcb:IO1PORTA"]
        if port then
            local f = port.fields["Service Mode"]
            if f then f:set_value(1); test_field = f end
        end
    end
end)
emu.register_frame_done(function()
    frame = frame + 1
    if test_mode then
        if test_field == nil then
            local f = io.open(outdir .. "/ports.txt", "w")
            for tag, port in pairs(manager.machine.ioport.ports) do
                for name, field in pairs(port.fields) do
                    f:write(tag .. " | " .. name .. " | mask=" .. tostring(field.mask) .. "\n")
                    if name == "Service Mode" then test_field = field end
                end
            end
            f:close()
            if test_field == nil then test_field = false end
        end
        if test_field then test_field:set_value(1) end
    end
    if done or frame < frame_target then return end
    done = true
    local main = manager.machine.devices[":mainpcb:maincpu"].spaces["program"]
    dump(main, 0x0C0000, 0x8000, outdir .. "/tileram.bin")
    dump(main, 0x0D0000, 0x800,  outdir .. "/textram.bin")
    dump(main, 0x120000, 0x2000, outdir .. "/paletteram.bin")
    dump(main, 0x100000, 0x800,  outdir .. "/spriteram.bin")
    dump(main, 0x2EC000, 0x800,  outdir .. "/roadram.bin")
    local f = io.open(outdir .. "/frame.txt", "w"); f:write(tostring(frame) .. "\n"); f:close()
    manager.machine.video:snapshot()
    manager.machine:exit()
end)
