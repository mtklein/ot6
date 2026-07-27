-- gen_ifrit_magicite.lua -- v0.6 leg 8: ifrit_doorstep (map 264, {3,7}
-- facing IFRIT) -> battle 70 -> the four-interaction esper hand-off ->
-- both magicite in the bag.  Mints magicite_ifrit_shiva.
--
-- THE HAND-OFF IS FOUR SEPARATE NPC INTERACTIONS, not one scene, and the
-- gates interlock (event_main.asm:95260-95385):
--
--   _cc7937  IFRIT {3,8}, sw $0646   first talk: walks SLOT_1 five tiles
--            RIGHT (so the party is left at {8,7} when the fight opens),
--            `battle 70`, then dlg $055F and `switch $0060=1 / $0273=1`
--   _cc7986  IFRIT, second talk      `switch $0272=1`; if $0274 also set,
--                                    fall into _cc79a4
--   _cc7992  SHIVA {9,6}, sw $0646   `if_switch $0060=0, EventReturn` --
--                                    she will not talk before the fight --
--                                    then `switch $0274=1`; if $0272 also
--                                    set, fall into _cc79a4
--   _cc79a4  the hand-off            `$0646=0 / $0647=1 / $0648=1 / $0273=0`
--                                    -- swaps both esper NPCs for MAGICITE
--                                    NPCs on the same two tiles
--   _cc79cd  MAGICITE {3,8}, sw $0647   give_genju IFRIT, `$0647=0`
--   _cc79dd  MAGICITE {9,6}, sw $0648   give_genju SHIVA, `$0648=0`
--
-- `give_genju` (EventCmd_86, field/event.asm:3238) sets bit (id-$36) of
-- $1A69, and GENJU::RAMUH=$36 / IFRIT=$37 / SHIVA=$38 (include/const.inc
-- :564-566), so the receipts are $1A69 bits 1 and 2 and they are what this
-- leg asserts -- not a switch that merely says a scene ran.
--
-- CORRECTION to docs/design/vector-route-recon.md §2.  The recon decoded
-- battle 70 as formation 439 containing "species $0109 Ifrit only", said
-- "Shiva $0108 is NOT in the formation ... she is not in any formation in
-- the game -- I swept all 576", and listed "does Shiva enter via the AI
-- script?" as probe 1.  Measured live at the doorstep, the formation
-- species words $57C0 read
--
--     0109 0108 0109 0108 FFFF FFFF
--
-- at battle start: **Shiva is in the formation from the first frame.**  No
-- AI-script entrance is involved.  (gen_ifrit_doorstep.lua's post-mint
-- verification is where that is measured; it is re-asserted below.)
--
-- The fight itself is cleared with the route's kill-bit idiom.  That is
-- deliberate: this generator's job is to bank the state, and neither
-- _cc7937's tail nor _cc79a4 reads a battle switch (`if_b_switch`), so the
-- win latches on control return -- recon probe 5, confirmed by $0060/$0273
-- below.  The combat contract for Ifrit and Shiva belongs in a suite test
-- booted on ifrit_doorstep.mss, the way battle_ultros2 hangs off
-- ultros2_doorstep.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hands off while a scene owns
-- it, edge-A through dialogs.  Used to walk INTO a trigger whose scene then
-- takes over -- the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- STOP TAPPING once we are where we were going.  The terminator
        -- wants 16 consecutive calm frames on the target, and an eager tap
        -- walks straight off it before the count gets there: the first
        -- version of this rode the chute correctly to (10,45) and then
        -- tapped itself to (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end


-- Hold a direction into an NPC and edge-press A until `pred` latches.
-- The direction press is safe because every NPC this leg talks to occupies
-- the destination tile, so the step is refused and only the facing takes
-- (the face-an-NPC idiom).  Hands off entirely while a scene owns control.
local function talkTo(dir, pred, maxFrames, what)
  local ph, calm, hb = 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("talkTo(%s) f%d (%d,%d) ctl=%s dlg=%s batt=%s",
          dir, H.frame, H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.dialogWaiting()), tostring(H.battleLoadStarted())))
      end
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not settled() or pred() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a", dir } or { dir })
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/ifrit_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 264, "booted on map 264")
    H.assertEq(H.fieldX(), 3, "boot x -- Ifrit's doorstep")
    H.assertEq(H.fieldY(), 7, "boot y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 2, "booted facing DOWN")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR at boot")
    H.assertEq(H.readByte(0x1A69) & 0x06, 0,
      "neither IFRIT nor SHIVA owned at boot ($1A69 bits 1-2)")
    H.log(partyReport("ifrit_doorstep"))
  end),

  -- 1. A into IFRIT -> _cc7937 -> battle 70.  Confirm the formation before
  --    touching it: this is the fight the leg exists to pass through, and
  --    a kill-bit applied to the WRONG battle would look identical in the
  --    log without this.
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.hold({ "a", "down" }), H.waitFrames(4), H.hold({ "down" }), H.waitFrames(4),
  }, "A into IFRIT -> battle 70"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[battle 70] formation = %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    H.assertEq(H.formationHas({ [0x0109] = true }), true, "battle 70 has IFRIT $0109")
    H.assertEq(H.formationHas({ [0x0108] = true }), true,
      "battle 70 has SHIVA $0108 FROM THE FIRST FRAME -- the recon's "
      .. "'Shiva is in no formation in the game' is wrong")
    H.screenshot("ifrit_battle")
  end),

  -- 2. clear it and ride the post-battle scene to $0060 / $0273
  H.advanceStory(function() return sw(0x0060) == 1 and settled() end, 20000),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x0060), 1, "$0060 SET -- battle 70 won (recon probe 5: the "
      .. "kill-bit idiom does latch this fight)")
    H.assertEq(sw(0x0273), 1, "$0273 SET -- the alcove is locked until the hand-off")
    H.log(string.format("[after battle 70] at (%d,%d)", H.fieldX(), H.fieldY()))
    H.log(partyReport("ifrit_won"))
    H.screenshot("ifrit_won")
  end),

  -- 3. SHIVA at {9,6}: stand at {9,7} and face UP.  $0274.
  H.navTo(9, 7, { maxFrames = 9000 }),
  talkTo("up", function() return sw(0x0274) == 1 end, 12000,
    "talk SHIVA -> $0274"),

  -- 4. IFRIT again at {3,8}: $0272, which (with $0274 already set) falls
  --    straight into _cc79a4, the hand-off.
  H.navTo(3, 7, { maxFrames = 9000 }),
  talkTo("down", function() return sw(0x0647) == 1 and sw(0x0648) == 1 end,
    16000, "talk IFRIT -> $0272 -> the hand-off _cc79a4"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x0272), 1, "$0272 SET -- IFRIT spoken to after the fight")
    H.assertEq(sw(0x0274), 1, "$0274 SET -- SHIVA spoken to after the fight")
    H.assertEq(sw(0x0646), 0, "$0646 CLEAR -- both dying espers are gone")
    H.assertEq(sw(0x0647), 1, "$0647 SET -- IFRIT's magicite is on {3,8}")
    H.assertEq(sw(0x0648), 1, "$0648 SET -- SHIVA's magicite is on {9,6}")
    H.assertEq(sw(0x0273), 0, "$0273 CLEAR -- the alcove is unlocked again")
    H.screenshot("mrf_handoff")
  end),

  -- 5. the two magicite pickups
  talkTo("down", function() return (H.readByte(0x1A69) & 0x02) ~= 0 end, 12000,
    "take the IFRIT magicite -> $1A69 bit1"),
  H.navTo(9, 7, { maxFrames = 9000 }),
  talkTo("up", function() return (H.readByte(0x1A69) & 0x04) ~= 0 end, 12000,
    "take the SHIVA magicite -> $1A69 bit2"),
  H.waitFrames(60),

  H.call(function()
    H.assertEq(map(), 264, "still on map 264")
    H.assertEq(H.readByte(0x1A69) & 0x01, 0x01, "RAMUH still owned ($1A69 bit0)")
    H.assertEq(H.readByte(0x1A69) & 0x02, 0x02, "IFRIT owned (give_genju $37)")
    H.assertEq(H.readByte(0x1A69) & 0x04, 0x04, "SHIVA owned (give_genju $38)")
    H.assertEq(sw(0x0647), 0, "$0647 CLEAR -- IFRIT's magicite has been taken")
    H.assertEq(sw(0x0648), 0, "$0648 CLEAR -- SHIVA's magicite has been taken")
    -- the way onward was NO-PATH while Shiva stood on {9,6}; now it is not
    H.assertEq(H.bfsPath(9, 5) ~= nil, true,
      "the door to map 269 (9,5) is open now that {9,6} is clear")
    H.log(string.format("[magicite_ifrit_shiva] f%d map=%d (%d,%d) $1A69=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x1A69)))
    H.log(partyReport("magicite_ifrit_shiva"))
    H.screenshot("magicite_ifrit_shiva")
  end),
  H.saveState("magicite_ifrit_shiva.mss"),
  H.call(function()
    census("magicite_ifrit_shiva", {
      { 3, 5, "door -> map 270 (save room)" },
      { 9, 5, "door -> map 269 (onward)" },
      { 6, 6, "_cc75f6, back up to 263" },
    })
  end),
  H.logStep(function()
    return string.format("magicite_ifrit_shiva minted at frame %d -- map 264, "
      .. "$1A69=%02X (RAMUH+IFRIT+SHIVA)", H.frame, H.readByte(0x1A69))
  end),
})
