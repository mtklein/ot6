-- @suite savestate=fc_alcove
-- battle_procboost.lua -- what the boost multiplier (Ot6BoostDmg's x2/x4/x8)
-- does and does not reach, verb by verb, through the real menus.
--
-- The rule (ot6_boostdmg.asm header):
--   * a spell whose boost bought a tier is not multiplied: the QUEUED command
--     is magic/x-magic/lore/summon and the QUEUED attack is in Ot6FoldTbl;
--   * a weapon's own on-hit spell is not multiplied (owner ruling, v0.21):
--     the boost bought that weapon's swings, not a second boost on its cast;
--   * everything else past the command gate is.
-- The executing $b5/$b6 cannot tell these apart: a Fight's Blizzard Ice, an
-- Ice Rod used from Item and a folded Ice cast all run as command $02 with a
-- fold-table spell in $b6.
--
-- From fc_alcove (TERRA with Blizzard, LOCKE, SHADOW, EDGAR; Ice Rod,
-- MithrilKnife and Magicite in the bag): out of the alcove onto the
-- continent, pace to a random encounter, everyone Defends until every bank
-- holds 3, snapshot.  Each case restores that snapshot, Defends the other
-- windows until its actor's opens, presses R three times and plays the verb
-- through its menu.  No state is written.  Every Ot6BoostDmg call the actor
-- makes during the action is recorded ($11b0 in and out, $b5/$b6, $3a7c/$3a7d,
-- pending, OT6_WEAPSPELL).  Asserted:
--   magic   TERRA's Fire, boosted, runs as Fire 3 and leaves unmultiplied
--   fight   TERRA's Fight: every Blizzard Ice it casts leaves unmultiplied,
--           and the swings (command $00) do too; retried at longer idle waits
--           until a try casts (a 1-in-4 roll per hit)
--   throw   SHADOW's MithrilKnife ($01, also Ice's id) leaves x8
--   rod     LOCKE's Ice Rod from Item (runs as Ice 2) leaves x8
--   magicite  LOCKE's Magicite from Item: any damage its esper deals leaves x8
--           (which esper answers is the item's own roll; a harmless one is
--           logged, not failed)
-- Negative controls: f0484b6f (OT6_ROM/OT6_DBG) fails `rod` (Ice 2 read as a
-- folded cast); a build with Ot6WeaponSpellQueued's store NOPed fails `fight`.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local BOOST = 3
local MULT = 1 << BOOST
local TERRA, LOCKE, SHADOW = 0x00, 0x01, 0x03
local ICE_ROD, MITHRIL_KNIFE, MAGICITE = 0x36, 0x01, 0xF9
local FIRE, FIRE3 = 0x00, 0x09
local FIGHT_TRIES, MAGICITE_TRIES, WAIT_STEP = 12, 6, 48

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local ST_ITEM, ST_MAGIC, ST_THROW = 0x0A, 0x0E, 0x2D
local ITEMLIST, BATTINV = 0x4005, 0x2686
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local THROW_SCROLL, THROW_ROW = 0x8953, 0x895B
local MSCROLL, MCOL, MROW, MLISTPTR = 0x8913, 0x8917, 0x891B, 0x302C
local BANK, PEND = 0x3E9C, 0x3E9D
local HANDS = 0x3CA8
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_THROW = 0x00, 0x01, 0x02, 0x08

local slotOf, snap, armed = {}, nil, nil
local weapspell                               -- OT6_WEAPSPELL, off the dbg

local function cmdRow(slot, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + r * 3) == cmd then return r end
  end
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
end
local function spellCell(slot, id)
  local base = H.readWord(MLISTPTR + slot * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    if H.readByte(base + (cell + 1) * 4) == id then return cell end
  end
end
local function onHitSpell(item)
  if item == 0xFF then return nil end
  local b = H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + item * 30 + 0x12)
  if (b & 0x40) == 0 then return nil end
  return b & 0x3F
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  -- absent on a ROM that predates the weapon-spell flag (the f0484b6f
  -- negative control); the calls are then logged with ws=$FF
  local ok, ws = pcall(function() return H.sym("OT6_WEAPSPELL") end)
  weapspell = ok and (ws & 0xFFFF) or nil
  local bd = H.sym("Ot6BoostDmg")
  local b0, b1, b2 = bd & 0xFF, (bd >> 8) & 0xFF, (bd >> 16) & 0xFF
  local sites = {}
  for off = 0x020000, 0x02FFFC do
    if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == b0
       and H.readRomByte(off + 2) == b1 and H.readRomByte(off + 3) == b2 then
      sites[#sites + 1] = 0xC00000 + off + 4
    end
  end
  H.assertEq(#sites, 2, "Ot6BoostDmg has two call sites in bank $C2")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x ~= armed.slot * 2 then return end
    armed.calls[#armed.calls + 1] = {
      b5 = H.readByte(0xB5), b6 = H.readByte(0xB6), a7c = H.readByte(0x3A7C),
      a7d = H.readByte(0x3A7D), pend = H.readByte(PEND + x),
      ws = weapspell and H.readByte(weapspell) or 0xFF, din = H.readWord(0x11B0) }
  end, emu.callbackType.exec, bd, bd)
  for _, ret in ipairs(sites) do
    emu.addMemoryCallback(function()
      if armed == nil or armed.endF or #armed.calls == 0 then return end
      local c = armed.calls[#armed.calls]
      if c.dout == nil then c.dout = H.readWord(0x11B0) end
    end, emu.callbackType.exec, ret, ret)
  end
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) == armed.slot * 2 then armed.endF = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end
-- everyone but `except` Defends: RIGHT opens Def., A commits it
local function defendOthers(except)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

-- the list steer for each verb: the button that walks toward the wanted
-- row, or "a" on it; nil while the list is not up
local function listStep(c, st)
  local s = c.slot
  if c.verb == "throw" then
    if st ~= ST_THROW then return nil end
    local want
    for i = 0, 63 do
      local id = H.readByte(ITEMLIST + i * 3)
      if id == c.item then want = i break end
      if id == 0xFF then break end
    end
    assert(want, string.format("item $%02X is in the Throw list", c.item))
    local cur = H.readByte(THROW_SCROLL + s) + H.readByte(THROW_ROW + s)
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  elseif c.verb == "item" then
    if st ~= ST_ITEM then return nil end
    local want = battInvIdx(c.item)
    assert(want, string.format("item $%02X is in the battle bag", c.item))
    local cur = H.readByte(ITEMSCR + s) + H.readByte(ITEMROW + s)
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  elseif c.verb == "magic" then
    if st ~= ST_MAGIC then return nil end
    local cell = spellCell(s, c.spell)
    assert(cell, string.format("spell $%02X is in the Magic list", c.spell))
    local wr, wc = cell // 2, cell % 2
    local ar = H.readByte(MSCROLL + s) + H.readByte(MROW + s)
    local col = H.readByte(MCOL + s)
    if ar ~= wr then return ar < wr and "down" or "up" end
    if col ~= wc then return col < wc and "right" or "left" end
    return "a"
  end
end

local CMD_OF = { fight = CMD_FIGHT, throw = CMD_THROW, item = CMD_ITEM, magic = CMD_MAGIC }
local LIST_OF = { throw = ST_THROW, item = ST_ITEM, magic = ST_MAGIC }
local phase, held = "idle", nil
local function decide(c)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= c.slot then return nil end
    if H.readByte(PEND + c.slot * 2) < BOOST then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(c.slot, CMD_OF[c.verb])
    assert(want, c.name .. ": the actor has the command")
    local cur = H.readByte(CMDROW + c.slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = LIST_OF[c.verb] and "list" or "target"
    return "a"
  end
  if phase == "list" then
    if st == ST_CMD then return "a" end            -- the A was not taken
    local b = listStep(c, st)
    if b == "a" then
      -- an item that picks its own target commits on this press
      c.pendAtConfirm, armed = H.readByte(PEND + c.slot * 2), c
      phase = "target"
    end
    return b
  end
  if phase == "target" then
    if H.readByte(MENU) == 0 or a ~= c.slot then phase = "sent" return nil end
    if st == ST_CMD or st == LIST_OF[c.verb] then return "a" end   -- not taken
    if st ~= ST_TGT then return nil end
    c.pendAtConfirm, armed = H.readByte(PEND + c.slot * 2), c
    phase = "confirmed"
    return "a"
  end
end

local function describe(k)
  return string.format("b5=$%02X b6=$%02X 3a7c=$%02X 3a7d=$%02X p%d ws=$%02X %d->%s",
    k.b5, k.b6, k.a7c, k.a7d, k.pend, k.ws, k.din, tostring(k.dout))
end

-- one try of a case from the snapshot; `c.done(c)` says whether the try
-- produced the thing the case is about (nil = any try does)
local function tryCase(c, n)
  local req, waited, skip = nil, 0, false
  return {
    H.call(function()
      skip = c.hit ~= nil
      if skip then return end
      H.setPad({})
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      if skip then return end
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      c.slot = slotOf[c.char]
      c.calls, c.endF, c.pendAtConfirm = {}, nil, nil
      c.wait = (n - 1) * WAIT_STEP
      tick, phase, held, waited = 0, "reach", nil, 0
    end),
    H.driveUntil(function() return skip or phase == "sent" end, 6000 + (n - 1) * WAIT_STEP, {
      H.call(function()
        if phase == "reach" then
          -- Defend the other windows until this actor's opens, then idle
          -- there for the try's wait
          if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
             and (H.readByte(ACTOR) & 3) == c.slot then
            H.setPad({})
            waited = waited + 1
            if waited >= c.wait then phase, tick = "boost", 0 end
          else
            defendOthers(c.slot)
          end
          return
        end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, string.format("%s, try %d", c.name, n)),
    H.driveUntil(function() return skip or (c.endF ~= nil and H.frame >= c.endF + 30) end, 6000, {
      H.call(function() defendOthers(c.slot) end),
    }, c.name .. " resolves, try " .. n),
    H.call(function()
      if skip then return end
      armed = nil
      H.setPad({})
      local parts = {}
      for _, k in ipairs(c.calls) do parts[#parts + 1] = describe(k) end
      H.log(string.format("[procboost] %s try %d (wait %d): pending at confirm %s: %s",
        c.name, n, c.wait, tostring(c.pendAtConfirm),
        #parts > 0 and table.concat(parts, " | ") or "no Ot6BoostDmg call"))
      if c.done == nil or c.done(c) then
        c.hit = { calls = c.calls, n = n, pendAtConfirm = c.pendAtConfirm }
      end
    end),
  }
end

local function isCast(c, k) return k.b5 == CMD_MAGIC and k.b6 == c.castSpell end
local CASES = {
  { name = "magic", char = TERRA, verb = "magic", spell = FIRE, tries = 1 },
  { name = "fight", char = TERRA, verb = "fight", tries = FIGHT_TRIES,
    done = function(c)
      for _, k in ipairs(c.calls) do if isCast(c, k) then return true end end
      return false
    end },
  { name = "throw", char = SHADOW, verb = "throw", item = MITHRIL_KNIFE, tries = 1 },
  { name = "rod", char = LOCKE, verb = "item", item = ICE_ROD, tries = 1 },
  { name = "magicite", char = LOCKE, verb = "item", item = MAGICITE, tries = MAGICITE_TRIES,
    done = function(c) return #c.calls > 0 end },
}

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function() installObservers() end),
  -- the alcove draws no encounters: out by its exit, 358 (8,8) north of the
  -- SavePoint, onto the continent (394), as gen_fc_escape does
  H.navTo(8, 9, { maxFrames = 3000 }),
  H.driveUntil(function() return (H.mapId() & 0x3FF) == 394 end, 1800, {
    H.call(function()
      if not H.hasControl() then H.setPad({}) return end
      H.setPad({ up = true })
    end),
  }, "alcove -> 394"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, "control on 394", 10),
  (function()
    local lane
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "left", "right", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
          if lane == nil then H.setPad({}) return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
    }, "a random encounter")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(BCHID + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    for _, ch in ipairs({ TERRA, LOCKE, SHADOW }) do
      assert(slotOf[ch], string.format("character %d is in the battle", ch))
    end
    -- the Fight case needs a weapon whose on-hit spell is a fold-table spell
    -- (the case the executing bytes misread); TERRA's Blizzard casts Ice
    local fold, base = {}, H.sym("Ot6FoldTbl") & 0x3FFFFF
    for i = 0, 23 do fold[H.readRomByte(base + i)] = true end
    local s = slotOf[TERRA]
    local item = H.readByte(HANDS + s * 2)
    local sp = onHitSpell(item) or onHitSpell(H.readByte(HANDS + s * 2 + 1))
    assert(sp and fold[sp], string.format("TERRA's weapon ($%02X) casts a fold-table spell on hit", item))
    CASES[2].castSpell = sp
    H.log(string.format("[procboost] TERRA slot %d holds $%02X, casts spell $%02X on hit "
      .. "(in Ot6FoldTbl); LOCKE slot %d, SHADOW slot %d", s, item, sp, slotOf[LOCKE], slotOf[SHADOW]))
  end),
  -- everyone Defends until every bank holds BOOST, then snapshot the next window
  H.driveUntil(function() return snap ~= nil end, 30000, {
    H.call(function()
      local full = true
      for _, ch in ipairs({ TERRA, LOCKE, SHADOW }) do
        if H.readByte(BANK + slotOf[ch] * 2) < BOOST then full = false end
      end
      if full and H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD then
        H.setPad({})
        snap = H.requestSaveState()
        return
      end
      defendOthers(-1)
    end),
  }, "every bank at " .. BOOST),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot") end),
}
for _, c in ipairs(CASES) do
  for n = 1, c.tries do
    for _, s in ipairs(tryCase(c, n)) do steps[#steps + 1] = s end
  end
end

steps[#steps + 1] = H.call(function()
  local by = {}
  for _, c in ipairs(CASES) do by[c.name] = c end
  local function one(c, pred, what)
    for _, k in ipairs(c.hit.calls) do if pred(k) then return k end end
    error(c.name .. ": no Ot6BoostDmg call that is " .. what, 0)
  end
  for _, c in ipairs(CASES) do
    H.assertEq(c.hit ~= nil or c.name == "magicite", true, c.name .. ": the case happened")
    if c.hit then H.assertEq(c.hit.pendAtConfirm, BOOST, c.name .. ": pending boost at the confirm") end
  end

  -- magic: the fold bought Fire 3; no multiplier on top
  local k = one(by.magic, function(k) return k.b5 == CMD_MAGIC end, "the cast")
  H.assertEq(k.b6, FIRE3, "magic: the boosted Fire runs as Fire 3 (the tier the boost bought)")
  H.assertEq(k.dout, k.din, string.format("magic: Fire 3 leaves unmultiplied (%d in)", k.din))

  -- fight: the weapon's own spell and the swings leave unmultiplied
  local casts = 0
  for _, k in ipairs(by.fight.hit.calls) do
    if isCast(by.fight, k) then
      casts = casts + 1
      H.assertEq(k.pend, BOOST, "fight: the cast arrives with the pending boost")
      H.assertEq(k.dout, k.din, string.format(
        "fight: the weapon's own spell $%02X leaves unmultiplied (%d in)", k.b6, k.din))
    elseif k.b5 == CMD_FIGHT then
      H.assertEq(k.dout, k.din, string.format("fight: a swing leaves unmultiplied (%d in)", k.din))
    end
  end

  -- throw: MithrilKnife's id is Ice's, and a Throw is not a cast
  k = one(by.throw, function(k) return k.b5 == CMD_THROW end, "the throw")
  H.assertEq(k.a7d, MITHRIL_KNIFE, "throw: the queued attack is the knife")
  H.assertEq(k.dout, math.min(k.din * MULT, 0x7FFF), string.format(
    "throw: MithrilKnife leaves x%d (%d in)", MULT, k.din))

  -- rod: the Ice Rod runs as a command-$02 Ice 2 that nothing folded
  k = one(by.rod, function(k) return k.b5 == CMD_MAGIC end, "the rod's spell")
  H.assertEq(k.a7c, CMD_ITEM, "rod: the queued command is Item")
  H.assertEq(k.dout, math.min(k.din * MULT, 0x7FFF), string.format(
    "rod: the Ice Rod's spell $%02X leaves x%d (%d in)", k.b6, MULT, k.din))

  -- magicite: whatever damage its esper deals is multiplied
  local mc = 0
  if by.magicite.hit then
    for _, k in ipairs(by.magicite.hit.calls) do
      if k.pend == BOOST then
        mc = mc + 1
        H.assertEq(k.dout, math.min(k.din * MULT, 0x7FFF), string.format(
          "magicite: the esper's $%02X leaves x%d (%d in)", k.b6, MULT, k.din))
      end
    end
  end
  H.log(string.format("[procboost] verdict: magic skipped, %d weapon cast(s) unmultiplied "
    .. "(try %d), throw x%d, rod x%d, magicite %s", casts, by.fight.hit.n, MULT, MULT,
    mc > 0 and string.format("x%d on %d call(s)", MULT, mc) or "dealt no damage in the tries"))
end)

H.run({ maxFrames = 300000 }, steps)
