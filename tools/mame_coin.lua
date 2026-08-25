-- Press Coin 1 for four frames starting at frame XB_COIN (for audio captures).
local coin_frame = tonumber(os.getenv("XB_COIN") or "120")
local frame = 0
local field = nil
emu.register_frame_done(function()
    frame = frame + 1
    if field == nil then
        local port = manager.machine.ioport.ports[":mainpcb:IO1PORTA"]
        field = port and port.fields["Coin 1"] or false
    end
    if field and frame >= coin_frame and frame < coin_frame + 4 then field:set_value(1) end
    if field and frame == coin_frame + 4 then field:set_value(0) end
end)
