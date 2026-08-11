-- gen_esper_tubes_done.lua -- v0.6 step 11: esper_tubes_doorstep (map 274
-- {10,10} facing UP) -> UP + A onto {10,9} -> _cc7a60, the Cid/Kefka tube
-- room set piece -> six espers, CELES LEFT BEHIND, $0068=1.  Generates
-- esper_tubes.
--
-- _cc7a60 (event_main.asm:95456-96299) is ~850 lines and entirely
-- non-interactive once it starts, so it is ridden with advanceStory.  The
-- three things it does that the rest of v0.6 stands on:
--
--  * `give_genju MADUIN, PHANTOM, UNICORN, BISMARK, CARBUNKL, SHOAT`
--    (:95777-95782), six in one uninterruptible block.  EventCmd_86
--    (field/event.asm:3238) sets bit (id-$36) of $1A69, and the ids
--    (include/const.inc:564-585) are SHOAT $3b, MADUIN $3c, BISMARK $3d,
--    CARBUNKL $49, PHANTOM $4a, UNICORN $4d -- bits 5, 6, 7, 19, 20 and 23.
--    So the receipt is $1A69+0 gaining $E0 and $1A69+2 gaining $98, and
--    that is what is asserted, not a switch that merely says a scene ran.
--
--  * `delete_obj CELES / char_party CELES, 0 / party_chars LOCKE /
--    switch $02F6=0 / remove_equip CELES` (:96148-96158).  $02F6 is
--    $1EDE bit 6 -- the "available characters" word, not a story flag
--    (notes/field-ram.txt:1114-1116; field/event.asm:4443-4448) -- so this
--    is Celes leaving the ROSTER, and char_party 0 clears her $1850 party
--    nibble.  **This is where the v0.6 party size drops.**
--
--  * `switch $064B=1 / switch $0068=1` (:96298-96299) then
--    `player_ctrl_on`.  $0068 is what unlocks the lift trigger _cc7f43 on
--    {20,13} (`if_switch $0068=0, EventReturn`, :96313-96314), so it is
--    both the receipt for this step and the key to the next.
--
-- THE PARTY THIS LEAVES BEHIND is the load-bearing measurement of this
-- whole beat and it is asserted below rather than described.  Measured at
-- every entry point from the post-Opera checkpoint onward, $1850 read
-- LOCKE=$C1 CELES=$49 and every other character $00, i.e. an ACTIVE PARTY
-- OF TWO -- so what walks out of this room is LOCKE ALONE.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
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

-- (a tapInto helper used to sit here, DEFINED and never called -- the same
-- dead battle toolkit the other tube-step conversions deleted; its only
-- battle handling was the battle-clear write.  issue #75: this file now has
-- ZERO state writes -- the scene is ridden with real input only)

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


local boot = { 0, 0, 0, 0 }
local verifyReq, verifyLoad = nil, nil
local function espers()
  local t = {}
  for i = 0, 3 do t[i + 1] = H.readByte(0x1A69 + i) end
  return t
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/esper_tubes_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 274, "booted on map 274")
    H.assertEq(H.fieldX(), 10, "boot x")
    H.assertEq(H.fieldY(), 10, "boot y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "booted facing UP")
    H.assertEq(sw(0x0068), 0, "$0068 CLEAR at boot")
    H.assertEq(sw(0x02F6), 1, "$02F6 SET at boot -- CELES is in the roster")
    local e = espers()
    -- MEASURED boot roster, not assumed.  $1A69+0 = $0F is RAMUH(0),
    -- IFRIT(1), SHIVA(2), SIREN(3) -- Ifrit and Shiva are this beat's, the
    -- other two ride in from earlier steps.  The rest is recorded rather
    -- than asserted bit by bit, because what this step proves is the DELTA:
    -- boot0/boot2 are captured here and the post-scene assertion is
    -- boot | the six give_genju bits, so an esper arriving from somewhere
    -- else cannot be mistaken for one of these six.
    boot = { e[1], e[2], e[3], e[4] }
    H.assertEq(e[1] & 0x07, 0x07, "boot espers include RAMUH, IFRIT, SHIVA")
    H.assertEq(e[1] & 0xE0, 0x00,
      "boot espers do NOT include SHOAT(5), MADUIN(6) or BISMARK(7)")
    H.assertEq(e[3] & 0x98, 0x00,
      "boot espers do NOT include CARBUNKL(19), PHANTOM(20) or UNICORN(23)")
    H.log(string.format("[boot espers] $1A69 = %02X %02X %02X %02X",
      e[1], e[2], e[3], e[4]))
    H.log(partyReport("esper_tubes_doorstep"))
  end),

  -- 1. UP + A held: step onto {10,9} with $01B0 (facing up) and $01B4 (A
  --    down) both set, which is the only way _cc7a60 ever fires.
  (function() local n = 0
    return H.driveUntil(function()
      return n > 120 and not H.hasControl()
    end, 4000, {
      H.call(function() n = n + 1; H.setPad({ "a", "up" }) end),
    }, "UP + A onto {10,9} -> _cc7a60")
  end)(),
  H.release(),
  H.call(function()
    H.assertEq(H.fieldY(), 9, "the party is on the trigger tile")
    H.log(string.format("[tube scene] started at f%d", H.frame))
    H.screenshot("esper_tubes_scene")
  end),

  -- 2. ride the ~850-line set piece to its `switch $0068=1`
  H.advanceStory(function() return sw(0x0068) == 1 end, 60000,
    { playBattles = true }),
  H.waitUntil(settled, 9000, "control back after the tube-room scene", 5),
  H.waitFrames(90),

  H.call(function()
    local e = espers()
    H.assertEq(map(), 274, "still on map 274 after the scene")
    H.assertEq(sw(0x0068), 1, "$0068 SET -- the tube-room scene is done")
    H.assertEq(sw(0x064B), 1, "$064B SET")
    -- six espers, by bit, from give_genju
    H.assertEq(e[1], boot[1] | 0xE0,
      "$1A69+0 gained exactly SHOAT(5) MADUIN(6) BISMARK(7)")
    H.assertEq(e[2], boot[2], "$1A69+1 unchanged")
    H.assertEq(e[3], boot[3] | 0x98,
      "$1A69+2 gained exactly CARBUNKL(19) PHANTOM(20) UNICORN(23)")
    H.assertEq(e[4], boot[4], "$1A69+3 unchanged")
    -- Celes is gone: roster bit AND party nibble
    H.assertEq(sw(0x02F6), 0, "$02F6 CLEAR -- CELES has left the roster")
    H.assertEq(H.readByte(0x1850 + 6) & 0x07, 0,
      "CELES's $1850 party nibble is 0 -- she is out of the active party")
    -- ...and what is left is LOCKE, SABIN and EDGAR.
    --
    -- THIS USED TO ASSERT ONE, AND THAT ONE WAS THE DEFECT, NOT THE RULE.
    -- The tube-room scene takes exactly one member, CELES.  It left the
    -- party at one character only because the chain arrived here with two
    -- -- the party_menu at the end of the Zozo leave cutscene was answered
    -- with a bare START, committing just the forced {LOCKE, CELES} and
    -- leaving SABIN, EDGAR, CYAN and GAU in the pool (#21).  The number 1
    -- was this generator recording that loss as if it were the story.
    -- gen_zozo5_ramuh now seats SABIN and EDGAR in the two free slots, so
    -- four walk in and three walk out, and gen_n128's header note that the
    -- minecart is fought by one character is superseded from here.
    --
    -- Named, not just counted: a count alone would go green again if the
    -- chain lost EDGAR somewhere and picked up CYAN instead.
    local cur, n, who = H.readByte(0x1A6D), 0, {}
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == cur then n = n + 1; who[c] = true end
    end
    H.assertEq(n, 3,
      "THE ACTIVE PARTY IS THREE CHARACTERS -- everything from the minecart "
      .. "to the Cranes is fought at this size")
    H.assertEq(who[0x01] == true, true, "LOCKE is still in the active party")
    H.assertEq(who[0x05] == true, true, "SABIN is still in the active party")
    H.assertEq(who[0x04] == true, true, "EDGAR is still in the active party")
    H.assertEq(who[0x06], nil, "CELES is NOT -- the tube room took her")
    H.log(string.format("[esper_tubes] f%d map=%d (%d,%d) $1A69=%02X %02X %02X %02X",
      H.frame, map(), H.fieldX(), H.fieldY(), e[1], e[2], e[3], e[4]))
    H.log(partyReport("esper_tubes"))
    H.screenshot("esper_tubes")
  end),
  H.saveState("esper_tubes.mss"),
  -- RELOAD-VERIFIED (gen_sabin_gau's pattern): capture-calm does NOT imply
  -- reload-calm, so reload the parked moment and require it quiet.
  H.call(function() verifyReq = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(verifyReq, "generated-state verify: capture")
    verifyLoad = H.requestLoadState(verifyReq.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(verifyLoad, "generated-state verify: reload") end),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 274, "reload: still on map 274")
    H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
    H.assertEq(H.dialogWaiting(), false, "reload: no dialog pending")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "reload: controllable at rest")
    H.assertEq(sw(0x0068), 1, "reload: $0068 still SET")
    H.assertEq(H.readByte(0x1850 + 6) & 0x07, 0, "reload: CELES still out")
    H.log("generated-state verify: the reload stayed calm -- esper_tubes verified")
  end),

  H.call(function()
    census("esper_tubes", {
      { 20, 13, "the lift trigger _cc7f43, now unlocked by $0068" },
    })
  end),
  H.logStep(function()
    return string.format("esper_tubes generated at frame %d -- map 274, six "
      .. "espers taken, CELES gone, $0068=1", H.frame)
  end),
})
