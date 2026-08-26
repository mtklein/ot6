-- @suite savestate=vargas_won slow
-- battle_blitzgrey.lua -- MP costs: the Blitz menu greys what Sabin can't
-- afford, exactly as vanilla Magic greys a spell whose MP cost exceeds current
-- MP.
--
-- Vanilla Magic: UpdateEnabledMagic (battle_main.asm) compares each spell's MP
-- cost to the caster's current MP and sets a disabled bit; DrawMagicListText's
-- GetTextColor turns that bit into $04, OR'd into the row's $21 white
-- font-palette byte to make $25 (grey).  Blitz and Tools draw through the
-- tools-window shell rather than the magic list, so they never inherited that
-- code.  Ot6AbilityGrey (ot6.asm, bank F0) supplies it in the menu bank:
-- the Blitz row decorator feeds each row's MP cost to it and OR's the $00/$04 it
-- returns into that column's font byte, so an unaffordable name (and its
-- trailing MP cost, which shares the font scope) renders $25 grey instead of
-- $21 white.  The caster is $62ca (the active slot the decorators and magic's
-- own draw both index) and its live MP is $3c08,slot*2, the cell the
-- universal charge at CalcAttackEffect later subtracts from, so the menu greys
-- exactly what the charge would refuse.
--
-- Boots vargas_won (the real post-boss Sabin, learned set read off $1d28:
-- Pummel 4 MP and AuraBolt 10 MP at his real level), fights real ledge
-- encounters, and drives his pool across the affordability line using the
-- blitzes themselves: AuraBolts while the pool is rich, one Pummel to
-- finish, until current MP lands in [4,9], where AuraBolt is unaffordable and
-- Pummel is still affordable. The charge and the grey are shown to read the
-- same cell, in both directions on the same rows (rich pool: every row
-- white; spent pool: the expensive row grey).
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey):
--   1. rich pool: every learned blitz the real pool affords renders white,
--      including the row that greys below (so grey tracks MP, the old
--      pass-2 claim, made first).
--   2. spent-to boundary: with MP spent into [4,9], the expensive
--      learned blitz renders grey and the cheap one white on one screen.
--   3. the grey is the disabled bit: grey - white == $04, magic's own delta.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_TGT = 0x05, 0x30, 0x38
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, KNOWN = 0x202E, 0x4005, 0x1D28
local SABIN = 0x05
local BLITZ_ATK0 = 0x5D
local WHITE, GREY = 0x21, 0x25

local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local ATKNAME_0, NAME_SIZE = 0x51, 10
local function nameSeq(id)
  local t, rec = {}, id - ATKNAME_0
  for i = 0, NAME_SIZE - 1 do t[#t + 1] = H.readRomByte(ATKNAME + rec * NAME_SIZE + i) end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameSeq(id)) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

local function map() return H.mapId() & 0x1ff end

-- the save's learned ladder, and the two rows the boundary is built from
local learned = {}
local cheap, dear = nil, nil            -- min-cost and max-cost learned ids

local sabinSlot, sabinOfs = nil, 37 * SABIN
local function pool()
  if H.battleLoadStarted() and sabinSlot then
    return H.readWord(0x3C08 + sabinSlot * 2)
  end
  return H.readWord(0x160d + sabinOfs)
end

-- the spend plan: park the pool in [costOf(cheap), costOf(dear)-1].
local function planCast(mp)
  local cD, cC = costOf(dear), costOf(cheap)
  if mp >= cD + cC then return dear end
  if mp >= cD then return cheap end
  return nil
end

-- ------------------------------------------------------------------------
-- the per-frame driver: "spend" casts planCast's blitz on Sabin's menu;
-- "open" holds the list up. Bystanders Defend; battle dialogs are paged
-- with A; off-battle the lane is paced for the next natural encounter.
-- ------------------------------------------------------------------------
local mode = "spend"
local ph, lane, hb = 0, nil, -600
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then
    hb = H.frame
    H.log(string.format("[hb f%d] mode=%s pool=%d batt=%s menu=%02x actor=%d "
      .. "mstate=%02x map=%d", H.frame, mode, pool(),
      tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
      H.readByte(MSTATE), map()))
  end
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    -- field: pace the lane for the next encounter; page victory/EXP dialogs
    -- with A until control returns
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil          -- re-anchor at the next field return
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})     -- page battle dialogs
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= sabinSlot then
    local step = ph % 40
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local st = H.readByte(MSTATE)
  local wantBlitz = (mode == "spend") and planCast(pool()) or cheap
  if mode == "spend" and wantBlitz == nil then H.setPad({}) return end
  if st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_BLITZ then wantCell = i end
    end
    assert(wantCell, "SABIN's real command list carries Blitz")
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  elseif st == ST_TOOLS then
    if mode == "open" then H.setPad({}) return end
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == wantBlitz then entry = i end
    end
    if entry == nil then H.setPad({}) return end
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else H.setPad(edge and { a = true } or {}) end
  elseif st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == 0x01 then
    H.setPad({})
  else
    H.setPad(edge and { b = true } or {})
  end
end

local function openBlitzWindow(what)
  return H.repeatN(1, {
    H.call(function() mode = "open" end),
    H.driveUntil(function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == sabinSlot and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),
  })
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    local mask = H.readByte(KNOWN)
    for i = 0, 7 do
      if (mask >> i) & 1 == 1 then
        local id = BLITZ_ATK0 + i
        learned[#learned + 1] = id
        if cheap == nil or costOf(id) < costOf(cheap) then cheap = id end
        if dear == nil or costOf(id) > costOf(dear) then dear = id end
      end
    end
    local names = {}
    for _, id in ipairs(learned) do
      names[#names + 1] = string.format("%s(%d)", nameText(id), costOf(id))
    end
    H.log(string.format("$1d28 = $%02x as saved: %s", mask, table.concat(names, " ")))
    H.assertEq(#learned >= 2, true, "two learned blitzes -- a boundary needs both sides")
    H.assertEq(costOf(dear) > costOf(cheap), true,
      "the learned costs differ, so one screen can show white and grey at once")
    H.assertEq(costOf(dear) >= 2 * costOf(cheap), true,
      "the spend plan's remainder arithmetic holds (cMax >= 2*cMin) -- for "
      .. "Pummel 4 / AuraBolt 10 it does; a repricing that breaks this needs "
      .. "a new plan, not a pin")
    H.log(string.format("SABIN field MP as saved: %d", pool()))
    H.assertEq(pool() >= costOf(dear), true,
      "positive control: the saved pool can afford the dear blitz, so the "
      .. "first open has the white row that will later grey")
  end),

  -- first natural encounter
  H.driveUntil(function() return H.battleLoadStarted() end, 12600,
    { H.call(pulse), H.waitFrames(1) }, "a ledge encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == SABIN then sabinSlot = s end
    end
    assert(sabinSlot, "SABIN present (vargas_won party)")
    H.log(string.format("SABIN slot %d, battle pool %d", sabinSlot, pool()))
  end),

  -- 1. rich pool: every affordable row white --------------------------------
  openBlitzWindow("sabin's blitz window, rich pool"),
  H.call(function()
    local mp = pool()
    H.screenshot("blitz_grey_rich")
    for _, id in ipairs(learned) do
      local a = attrOf(nameSeq(id))
      local want = (mp >= costOf(id)) and WHITE or GREY
      H.log(string.format("  rich pool (%d MP): %-9s attr=%s want $%02x",
        mp, nameText(id), a and string.format("$%02x", a) or "nil", want))
      H.assertEq(a, want, string.format(
        "%s (cost %d, MP %d) renders %s at the rich pool", nameText(id),
        costOf(id), mp, want == WHITE and "white" or "grey"))
    end
    H.assertEq(pool() >= costOf(dear), true,
      "the rich-pool pass had the dear row white -- the row that greys below")
  end),

  -- 2. spend to the boundary with the blitzes themselves --------------------
  H.call(function() mode = "spend" end),
  H.driveUntil(function() return pool() < costOf(dear) end, 150000,
    { H.call(pulse), H.waitFrames(1) }, "the pool is spent into the boundary"),
  H.call(function()
    local mp = pool()
    H.log(string.format("pool after real casts: %d MP", mp))
    H.assertEq(mp >= costOf(cheap) and mp < costOf(dear), true, string.format(
      "the spend plan parked the pool in [%d,%d]: %s unaffordable, %s "
      .. "affordable -- both states on one screen",
      costOf(cheap), costOf(dear) - 1, nameText(dear), nameText(cheap)))
  end),

  -- ... and the boundary window: grey and white side by side ----------------
  openBlitzWindow("sabin's blitz window, spent pool"),
  H.call(function()
    local mp = pool()
    H.screenshot("blitz_grey_display")
    local aC, aD = attrOf(nameSeq(cheap)), attrOf(nameSeq(dear))
    local fmt = function(a) return a and string.format("$%02x", a) or "nil" end
    H.log(string.format("spent pool (%d MP): %s=%s %s=%s",
      mp, nameText(cheap), fmt(aC), nameText(dear), fmt(aD)))
    H.assertEq(aD, GREY, string.format(
      "%s (cost %d, MP %d) renders grey -- the charge priced it out",
      nameText(dear), costOf(dear), mp))
    H.assertEq(aC, WHITE, string.format(
      "%s (cost %d, MP %d) renders white -- still affordable",
      nameText(cheap), costOf(cheap), mp))
    H.assertEq(aD - aC, 0x04,
      "grey - white == $04, magic's own disabled-bit delta")
    H.log("PASSED: the blitz menu greys exactly what the SPENT pool cannot "
      .. "afford, and only that -- the charge and the grey read the same cell")
  end),
})
