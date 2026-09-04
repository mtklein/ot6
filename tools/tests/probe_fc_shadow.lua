-- probe_fc_shadow.lua -- is Shadow's NPC at 394 (10,16) already there at the
-- landing?  The cold-Continue map dump (probe_fc_bfs.lua) shows the object
-- map marking (10,16) occupied before any (70,29) return; the route doc
-- reads $035E as set only by that return's Yes branch.  Measure: read the
-- switch, walk to (10,15), face down, tap A, and see whether he joins.
-- A probe: reads and presses only.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local SHADOW = 0x03
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local FIGHT = { tactical = true, boost = true, bank = 2, items = true, healPercent = 50,
                magic = { [0] = { spell = 2 }, [1] = { spell = 2 } }, nuke = { 2 } }
local F = H.newFightDriver("fc", FIGHT)
local t = 0
H.run({ maxFrames = 30000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(394) and H.hasControl() end, 3000, "cold Continue to the landing SavePoint", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[shadow?] at the landing: $035E=%d $035F=%d $02F3=%d obj(10,16)=%02X shadow in party=%d",
      sw(0x035E), sw(0x035F), sw(0x02F3), H.readByte(0x7E2000 + 16 * 256 + 10), partyOf(SHADOW)))
  end),
  H.navTo(10, 15, { maxFrames = 6000, playBattles = "tactical", healer = 0, magic = FIGHT.magic, items = true }),
  H.driveUntil(function() return partyOf(SHADOW) ~= 0 or t > 500 end, 900, {
    H.call(function()
      t = t + 1
      if H.battleActive() or H.battleLoadStarted() then F.frame(); return end
      if H.dialogWaiting() then H.setPad(t % 24 < 3 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      local ph = t % 40
      if ph < 2 then H.setPad({ down = true })
      elseif ph >= 10 and ph < 14 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "talk down from (10,15)"),
  H.call(function()
    H.log(string.format("[shadow?] after the talk: shadow in party=%d $035E=%d $02F3=%d", partyOf(SHADOW), sw(0x035E), sw(0x02F3)))
    H.screenshot("fc_shadow_probe")
  end),
})
