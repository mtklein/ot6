-- @suite savestate=atma_entry slow
-- battle_tentacles4.lua -- the Tentacles' Seize on seat 4 (docs/design/bosses-wor.md block 1, wt/v052-tg-wor1):
-- battle_tentacles plays the route's own Tentacles, whose party is three (seat 4 empty), so a body's seat-4 announce,
-- claim and fire block are played here, with four seated.
--
-- No four-member party meets the Tentacles on the line, so the formation is STAGED, as battle_fuse stages the
-- CzarDragon's: from atma_entry (Kefka's Tower, four seated) the party paces into a random battle on map 331 and the
-- formation the battle loads is written to 454, the Tentacles (event battle 84's formation), at LoadBattleProp's
-- entry.  Then (DECLARED: every body's gauge held at 63, each standing member's HP at 9,999, and the seat-4 member's
-- Slow written each frame until a body claims seat 4):
--   seat 4    a body announces with its claim on seat 4 (its monster switch 3), the lit bit and the mark; its Seize
--             comes on its next turn, queued on seat 4, and holds the member in seat 4 (that body its seize attacker,
--             its hold switch set); the claim is clear after it.
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the formation word ($11E0) at LoadBattleProp, and the
-- writes above.  A mechanism test, not play.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): tent_seat4_rotated (the seat-4 fire
-- block's target CHAR_SLOT_4 -> CHAR_SLOT_3) is red at "seat 4: the Seize was queued on seat 4".
local H = dofile("tools/tests/lib/ot6.lua")
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/atma_entry.mss.lua"

local SPECIES = { 0x11B, 0x13C, 0x13D, 0x13E }
local SEIZE, LINE, FORMATION, MAP = 0xC8, 0xA0, 454, 331
local function map() return H.mapId() & 0x1ff end
local function rb(a) return H.readByte(a) end
local Ws = {}
for _, sp in ipairs(SPECIES) do Ws[#Ws + 1] = H.fuseWatch(sp, WRITE) end
local staged, slow4, C = false, true, {}
local function say(s) H.log(string.format("[tentacles4] f%d %s", H.frame, s)) end
local function up() return H.battleLoadStarted() end
local function claimOf(W)
  local e = W.ent()
  if not e then return nil end
  local sw = rb(0x3DAC + e) & 0x0F
  return sw == 1 and 0 or sw == 2 and 1 or sw == 4 and 2 or sw == 8 and 3 or nil
end
local function seizeFrom(W, i)
  for k = i or 1, #W.cmds do
    local c = W.cmds[k]
    if c.cmd == 0x0C and c.arg == SEIZE then return k, c end
  end
  return nil
end
local function defendUntil(pred, max)
  return H.lazy(function()
    local t0 = H.frame
    return H.kitBattle({}, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return not up() or pred() or H.frame - t0 >= max end })
  end)
end
-- the first line whose body's claim stands on seat 4 (index 3), no Seize after it yet
local function line4()
  for _, W in ipairs(Ws) do
    local i, c = W.find(0x21, LINE, 1)
    while i ~= nil do
      if claimOf(W) == 3 and seizeFrom(W, i) == nil then return W, i, c end
      i, c = W.find(0x21, LINE, i + 1)
    end
  end
  return nil
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in Kefka's Tower"),
  H.call(function()
    H.assertEq(map(), MAP, "atma_entry stands on map 331")
    local lb = H.sym("LoadBattleProp")
    emu.addMemoryCallback(function()
      if staged then return end
      staged = true
      H.log(string.format("[tentacles4] f%d the battle's formation $%03X -> %d (the Tentacles), staged at "
        .. "LoadBattleProp", H.frame, H.readWord(0x11E0) & 0x7FFF, FORMATION))
      WRITE.word(0x11E0, FORMATION)
    end, emu.callbackType.exec, lb, lb)
    emu.addEventCallback(function()
      if not up() then return end
      -- (DECLARED) the gauges held at 63; the seat-4 member's Slow until a claim stands on seat 4
      for _, W in ipairs(Ws) do
        local e = W.ent()
        if e and rb(0x3E88 + e) == 0 and rb(0x3E38 + e) ~= 63 then WRITE.byte(0x3E38 + e, 63) end
        if claimOf(W) == 3 then slow4 = false end
      end
      if slow4 and rb(0x3ED8 + 6) ~= 0xFF and (rb(0x3EF8 + 6) & 0x04) == 0 then WRITE.byte(0x3EF8 + 6, rb(0x3EF8 + 6) | 0x04) end
    end, emu.eventType.endFrame)
  end),
  H.paceToEncounter("tentacles4", 0),
  H.call(function()
    H.assertEq(staged, true, "the formation was staged at LoadBattleProp")
    local seated = 0
    for i = 0, 3 do if rb(0x3ED8 + 2 * i) ~= 0xFF then seated = seated + 1 end end
    say(string.format("the battle is up: seats $%02X $%02X $%02X $%02X", rb(0x3ED8), rb(0x3EDA), rb(0x3EDC), rb(0x3EDE)))
    H.assertEq(seated, 4, "four seated (the precondition: a member in seat 4)")
    for _, W in ipairs(Ws) do
      H.assertEq(W.slot() ~= nil, true, string.format("the Tentacle $%03X stands", W.species))
      W.on = true
      W.pin = { party = true }
    end
  end),
  defendUntil(function() return line4() ~= nil end, 40000),
  H.call(function()
    local W, i, c = line4()
    H.assertEq(W ~= nil, true, "seat 4: a body announced with its claim on seat 4")
    C.W, C.li, C.lc = W, i, c
    say(string.format("$%03X announced on its turn %d with its claim on seat 4", W.species, c.turn))
  end),
  defendUntil(function() return C.W.litBit() and C.W.vramMark() == C.W.FUSE_WORD end, 900),
  H.call(function()
    H.assertEq(C.W.litBit(), true, "seat 4: the lit bit is set for the announcing body")
    H.assertEq(C.W.vramMark(), C.W.FUSE_WORD, "seat 4: the lit-fuse mark stands")
  end),
  defendUntil(function() return seizeFrom(C.W, C.li) ~= nil end, 12000),
  defendUntil(function() return rb(0x3359 + 6) == C.W.ent() end, 600),
  H.call(function()
    local W = C.W
    local si, sc = seizeFrom(W, C.li)
    H.assertEq(si ~= nil, true, "seat 4: the Seize was dispatched after the announce")
    say(string.format("Seize on its turn %d, targets $%02X; seat 4's seize attacker $%02X", sc.turn, sc.tchars,
      rb(0x3359 + 6)))
    H.assertEq(sc.turn - C.lc.turn, 1, "seat 4: the Seize came on the body's next turn")
    H.assertEq(sc.tchars & 0x0F, 0x08, "seat 4: the Seize was queued on seat 4")
    H.assertEq(rb(0x3359 + 6), W.ent(), "seat 4: the Seize holds the member in seat 4")
    H.assertEq(rb(0x3DAC + W.ent()) & 0x8F, 0x80, "seat 4: the body holds (switch 7) and its claim is clear")
  end),
  H.logStep("[tentacles4] PASS: the Seize announced, claimed and held on seat 4 with four seated"),
})
