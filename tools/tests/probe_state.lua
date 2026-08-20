-- probe_state.lua -- read the field party/inventory state and dump it, then
-- stop.  A standing inspector: boot any checkpoint (OT6_SRAM_CHECKPOINT=...)
-- or savestate under it and see gear/espers/levels/bag in ~15s, no route
-- replay.  Raw ids; decode names in the shell against ff6/notes/battle-lists.
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/thamasa-night-v1 \
--     OT6_TIMEOUT=300 tools/tests/run.sh tools/tests/probe_state.lua
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function rec(c)  return 0x1600 + 37 * c end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07)
                              == (H.readByte(0x1A6D) & 0x07) end

H.run({ maxFrames = 30000 }, {
  -- cold Continue; thamasa-night-v1 lands on the WORLD map at (249,128)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.driveUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldX() == 249
       and H.worldY() == 128
  end, 6000, {
    H.call(function()
      probeBootPh = ((probeBootPh or 0) + 1) % 48
      H.setPad((probeBootPh < 8) and { "a" } or {})
    end),
  }, "world control at (249,128)"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[state] gil=%d",
      H.readByte(0x1860) + H.readByte(0x1861) * 256
        + H.readByte(0x1862) * 65536))

    -- espers owned: $1A69-$1A6C, one bit each, RAMUH=bit0
    local ow = {}
    for b = 0, 3 do ow[#ow + 1] = string.format("%02X", H.readByte(0x1A69 + b)) end
    H.log("[state] espers-owned $1A69-6C: " .. table.concat(ow, " "))

    -- per active character
    for c = 0, 15 do
      if inParty(c) then
        local base = rec(c)
        local slots = {}
        for s = 0, 5 do
          slots[#slots + 1] = string.format("%02X", H.readByte(base + 0x1F + s))
        end
        H.log(string.format(
          "[state] char %d: Lv%d HP %d/%d MP %d/%d esper=%02X equip[w/sh/he/ar/r1/r2]=%s",
          c, H.readByte(base + 0x08),
          H.readWord(base + 0x09), H.readWord(base + 0x0B) & 0x3FFF,
          H.readWord(base + 0x0D), H.readWord(base + 0x0F),
          H.readByte(base + 0x1E), table.concat(slots, " ")))
      end
    end

    -- full inventory: id + count where count>0, $1869 ids / $1969 counts
    local inv = {}
    for i = 0, 255 do
      local id, n = H.readByte(0x1869 + i), H.readByte(0x1969 + i)
      if n > 0 and id ~= 0xFF then
        inv[#inv + 1] = string.format("%02X:%d", id, n)
      end
    end
    H.log("[state] inventory (id:count): " .. table.concat(inv, " "))
    H.log("[state] done")
    emu.stop(0)
  end),
})
