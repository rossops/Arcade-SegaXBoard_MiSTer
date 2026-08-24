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
-- The sprite list the chip renders is the one in sprite RAM at the moment
-- of the $110000 write (MAME swaps buffers there). Capture it on every
-- write; the last capture before the target frame is what the PNG shows.
local main_space = nil
local tap = nil
local road_rtap = nil
local road_wtap = nil

emu.register_frame_done(function()
    frame = frame + 1
    if tap == nil then
        main_space = manager.machine.devices[":mainpcb:maincpu"].spaces["program"]
        tap = main_space:install_write_tap(0x110000, 0x11ffff, "xb_sprswap", function(offset, data, mask)
            if not done then dump(main_space, 0x100000, 0x800, outdir .. "/spritelist.bin") end
        end)
        -- road RAM is swapped into the display buffer on a control read; the
        -- sub CPU owns the road ($EE000 in its map). Save the RAM at that
        -- moment, and the control value on write.
        local sub_space = manager.machine.devices[":mainpcb:subcpu"].spaces["program"]
        road_rtap = sub_space:install_read_tap(0xee000, 0xeffff, "xb_roadswap", function(offset, data, mask)
            if not done then dump(sub_space, 0xec000, 0x800, outdir .. "/roadbuf.bin") end
        end)
        road_wtap = sub_space:install_write_tap(0xee000, 0xeffff, "xb_roadctl", function(offset, data, mask)
            if not done then
                local f = io.open(outdir .. "/roadctl.txt", "w"); f:write(string.format("%d\n", data & 7)); f:close()
            end
        end)
    end
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
