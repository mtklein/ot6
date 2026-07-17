-- probe_whelkclass.lua -- M3 evidence probe on the REAL first boss.
--
--   tools/tests/run.sh tools/tests/probe_whelkclass.lua
--
-- Needs build/states/whelk_doorstep.mss.lua (minted by gen_whelk.lua on
-- the current ROM). Steps onto the trigger, enters the Whelk fight, and
-- proves what battle_class's guard lab cannot:
--
--   1. the authored $0134 'Head' record seeds live: shields 4, piercing
--      class-weak (m1 had authored $0135, the WoR presenter's head, so
--      the real head used to seed by formula = 2); the shell ($0100)
--      seeds shieldless
--   2. class chip + class codex on species >= $100: a piercing Fight
--      chips the head, and sram $316190+$134 learns the bit (the
--      pinned-i16 codex stretch working on a big species id)
--   3. the m1 element-codex i8 truncation fix: fire-weak-poked whelk
--      parts beamed until the element reveals -- the ELEMENT codex byte
--      lands at $316010+species, and the species' truncated neighbor
--      ($316010 + (species & $ff)) stays clean, where the m1 write
--      used to land
--
-- Also screenshots the reveal moment ("Weak against piercing" battle
-- message) right after the first class chip.
--
-- NO MENUS ARE DRIVEN: battles that open with a scripted battle dialog
-- ("VICKS: Hold it!") draw every menu with garbage-staged rows and
-- reject deep list selections -- a pre-M3 bug (reproduced on the
-- committed ROM; see probe_whelkmenu.lua). Instead this borrows
-- battle_hits's berserk trick twice over:
--   - terra: berserk + magitek status CLEARED + a Fight-only command
--     list + a dirk in hand -> auto-Fight = piercing weapon chips
--   - vicks/wedge: berserk + magitek status KEPT -> RandMagitekAction
--     rolls beams $83-$86, fire beam included -> element chips
-- (TekMissile is NOT in the berserk pool -- RandMagitek is hard-coded
-- to $83+rand(4) -- so ability-class evidence lives in
-- probe_tekmissile.lua, in the dialog-free guard fight.)
--
-- The savestate restores the mint-time SRAM (zeroed by the harness srm
-- wipe), so the battle seed does a fresh 'O7' codex init and every
-- reveal below starts cold.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"

local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end

-- monster-slot accessors (slot = 0..5, table byte = base + slot*2)
local hs, ss       -- head slot, shell slot
local terra        -- terra's party slot (char id 0)
local function headShields() return H.readByte(0x3E40 + hs * 2) end
local function headCWeak() return H.readByte(0x3EA4 + hs * 2) end
local function headCRev() return H.readByte(0x3EA5 + hs * 2) end
local function headERev() return H.readByte(0x3E91 + hs * 2) end

local aPhase = 0
local classWrites = {}

-- keepalive: stray hits on the shell eat MegaVolt counters ("still
-- lethal at level 1"), and the head must outlive the probing
local function keepalive()
  H.writeWord(0x3BF4, 999); H.writeWord(0x3BF6, 999)
  H.writeWord(0x3BF8, 999)
  H.writeWord(0x3BFC + hs * 2, 1600)
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- the deliberate step onto (42,5): gen_whelk's exact drive
  H.driveUntil(function() return whelk() end, 2200, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelk() then H.setPad({}); return end
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),

  -- 1. the authored head record, live
  H.call(function()
    for slot = 0, 5 do
      local sp = H.readWord(0x57C0 + slot * 2)
      if sp == 0x0134 then hs = slot end
      if sp == 0x0100 then ss = slot end
    end
    H.assertEq(hs ~= nil and ss ~= nil, true, "head+shell slots found")
    H.log(string.format("head slot %d, shell slot %d", hs, ss))
    H.assertEq(headShields(), 4, "head seeds the authored 4 shields")
    H.assertEq(headCWeak(), 0x02, "head seeds authored piercing-weak")
    H.assertEq(headCRev(), 0, "nothing revealed on a fresh codex")
    H.assertEq(H.readByte(0x3E40 + ss * 2), 0, "shell seeds shieldless")
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot * 2) == 0 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "terra found in the party")
    -- watch every class-byte load for the rest of the fight
    emu.addMemoryCallback(function(addr, value)
      classWrites[value] = (classWrites[value] or 0) + 1
    end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
  end),

  -- lab setup: dismiss the opening dialog, then berserk the party.
  -- terra gets a dirk and a Fight-only list (magitek bit cleared);
  -- vicks/wedge keep magitek status and roll random beams. the shell
  -- is also poked pierce-weak so either target yields chip evidence
  -- (reveal+codex fire even on a shieldless monster).
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
    H.pressButtons({ "a" }, 4),
    H.waitFrames(56),
  }, "opening dialog dismissed (first menu up)"),
  H.call(function()
    H.setPad({})
    H.writeByte(0x3EA4 + ss * 2, 0x02)     -- shell: pierce-weak lab poke
    H.writeByte(0x3CA8 + terra * 2, 0x00)  -- terra's right hand: Dirk
    keepalive()
    for slot = 0, 3 do                     -- entries are [cmd,d,d] x4
      H.writeByte(0x202E + slot * 12, 0x00)
      H.writeByte(0x2031 + slot * 12, 0xFF)
      H.writeByte(0x2034 + slot * 12, 0xFF)
      H.writeByte(0x2037 + slot * 12, 0xFF)
      local st2 = 0x3EE5 + slot * 2
      H.writeByte(st2, H.readByte(st2) | 0x10)          -- berserk
    end
    local st1 = 0x3EE4 + terra * 2         -- terra fights; others beam
    H.writeByte(st1, H.readByte(st1) & 0xF7)
    H.log(string.format("berserk lab armed: terra slot %d fights with a dirk",
      terra))
  end),

  -- 2. a piercing Fight chips a whelk part; catch the reveal message
  H.driveUntil(function()
    return ((headCRev() | H.readByte(0x3EA5 + ss * 2)) & 0x02) == 0x02
  end, 12000, {
    H.call(keepalive),
    H.waitFrames(15),
  }, "a piercing fight class-chips a whelk part"),
  H.waitFrames(12),
  H.call(function()
    H.screenshot("whelkclass_pierce_msg")
    local shellRev = H.readByte(0x3EA5 + ss * 2)
    local hit = (headCRev() & 2) == 2 and 0x134 or 0x100
    H.log(string.format("revealed on species %03x (head crev %02x shell crev %02x)",
      hit, headCRev(), shellRev))
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "piercing loads observed on the class byte")
    H.assertEq(sram(0x316190 + hit) & 0x02, 0x02,
      "class codex learned piercing for a species >= $100")
    if hit == 0x134 then
      H.assertEq(headShields() < 4, true, "the reveal also chipped the head")
    end
    local parts = {}
    for v, n in pairs(classWrites) do
      parts[#parts + 1] = string.format("%02x:%d", v, n)
    end
    table.sort(parts)
    H.log("class byte writes so far: " .. table.concat(parts, " "))
  end),

  -- 3. the element-codex fix on species >= $100: both whelk parts go
  -- fire-weak; vicks/wedge's random beams find one eventually
  H.call(function()
    H.writeByte(0x3BE8 + hs * 2, H.readByte(0x3BE8 + hs * 2) | 0x01)
    H.writeByte(0x3BE8 + ss * 2, H.readByte(0x3BE8 + ss * 2) | 0x01)
  end),
  H.driveUntil(function()
    return ((headERev() | H.readByte(0x3E91 + ss * 2)) & 0x01) == 0x01
  end, 15000, {
    H.call(keepalive),
    H.waitFrames(15),
  }, "a random fire beam element-chips a whelk part"),
  H.call(function()
    H.setPad({})
    local hit = (headERev() & 1) == 1 and 0x134 or 0x100
    H.assertEq(sram(0x316010 + hit) & 0x01, 0x01, string.format(
      "element codex learned fire AT species %03x (the i8 fix)", hit))
    H.assertEq(sram(0x316010 + (hit & 0xFF)), 0, string.format(
      "and %03x's truncated neighbor $%02x stayed clean", hit, hit & 0xFF))
    H.screenshot("whelkclass_final")
    H.log(string.format("head shields now %d, crev %02x, erev %02x",
      headShields(), headCRev(), headERev()))
  end),
})
