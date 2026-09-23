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
-- Boots vargas_won (the real post-boss Sabin, learned set read off $1d28,
-- priced off Ot6AbilityCostTbl: the cheapest and the dearest learned blitz
-- are the boundary's two rows), fights real ledge encounters, and drives his
-- pool across the affordability line using the blitzes themselves: the dear
-- blitz while the pool is rich, the cheap one to finish, until current MP
-- lands in [cheap, dear-1], where the dear row is unaffordable and the cheap
-- one still affordable.  Whatever the ledge deals -- a status that takes
-- Sabin's window, a party worn down, a level-up refill -- is played through
-- the way a person plays it (the driver's notes below).  The charge and the
-- grey are shown to read the same cell, in both directions on the same rows
-- (rich pool: every row white; spent pool: the expensive row grey).
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey):
--   1. rich pool: every learned blitz the real pool affords renders white,
--      including the row that greys below (so grey tracks MP, the old
--      pass-2 claim, made first).
--   2. spent-to boundary: with MP spent into the band, the expensive
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
local function inBand(mp) return mp >= costOf(cheap) and mp < costOf(dear) end

-- Can Sabin's next full gauge open a command window?  The mirror of
-- CheckPlayerAction's status gate (battle_main.asm:1470): STATUS1 $3EE4,x
-- {ZOMBIE $02, PETRIFY $40, DEAD $80} and STATUS2 $3EE5,x {BERSERK $10,
-- CONFUSE $20, SLEEP $80} each send the turn to CancelAction instead of the
-- menu (battle_bushidogrey's canMenu).  The status bytes are the previous
-- battle's until the pack's HP table fills, so this is only read off a
-- battle whose pack has HP.
local ST1_NOMENU, ST2_NOMENU = 0x02 | 0x40 | 0x80, 0x10 | 0x20 | 0x80
local function packHp()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s * 2) end
  return t
end
local function sabinStatus()
  if not sabinSlot then return 0, 0 end
  return H.readByte(0x3EE4 + sabinSlot * 2), H.readByte(0x3EE5 + sabinSlot * 2)
end
local function sabinDenied()
  if not (sabinSlot and H.battleLoadStarted()) or packHp() == 0 then return false end
  local s1, s2 = sabinStatus()
  return (s1 & ST1_NOMENU) ~= 0 or (s2 & ST2_NOMENU) ~= 0
end
-- Is anyone down, or badly hurt?  battle_kitrefuse's shape (and
-- battle_stealmp's): an all-Defend party never ends a fight on its own.
local function partyHurt()
  for s = 0, 3 do
    local h, m = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
    if m > 0 and m < 9999 and (h == 0 or h * 100 // m < 55) then return true end
  end
  return false
end

-- ------------------------------------------------------------------------
-- the per-frame driver: "open" holds Sabin's list up; "boundary" casts
-- planCast's blitz at each of Sabin's windows and, once the pool is in the
-- band, holds the list up instead.  Battle dialogs are paged with A.
--
-- Bystanders Defend, so Sabin gets the turns -- until the battle cannot
-- serve the spend: Sabin has lost his window to a status (measured on the
-- regenerated vargas_won, 2026-09-23: a Trilium's hit poisoned him at f4672
-- and a Cirpius's petrified him at f5785, and three Defending bystanders
-- were ground to 0 over the next 35,000 frames with the pool stuck at 15;
-- build/attempts/wt/regen-suites/), or the party is hurt.  Then they swing
-- and end it.  Off-battle, the route's own care stop runs after every
-- battle (Tonics, a Soft for a statue, a Fenix Down for the fallen, never a
-- cast, so Sabin's pool is his own), then the lane is paced for the next
-- natural encounter.
-- ------------------------------------------------------------------------
local mode = "open"
local ph, lane, hb = 0, nil, -600
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local care, careDue = nil, false
local swingSaid = nil
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then
    hb = H.frame
    local s1, s2 = sabinStatus()
    H.log(string.format("[hb f%d] mode=%s pool=%d batt=%s menu=%02x actor=%d "
      .. "mstate=%02x map=%d sabin st1=%02x st2=%02x", H.frame, mode, pool(),
      tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
      H.readByte(MSTATE), map(), s1, s2))
  end
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    -- a care stop in progress owns the pad until it is done, menu and all
    -- (the menu takes field control away, so this comes first)
    if care then
      care.frame()
      if care.done() then care, careDue = nil, false end
      return
    end
    -- field: page victory/EXP dialogs with A until control returns
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
    if careDue then
      care = H.newCareDriver({ tag = "blitzgrey care", threshold = 0.65 })
      care.frame()
      if care.done() then care, careDue = nil, false end
      return
    end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
      if lane == nil then H.setPad({}) return end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil          -- re-anchor at the next field return
  care, careDue = nil, true     -- care at the next field control
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})     -- page battle dialogs
    return
  end
  local a = H.readByte(ACTOR)
  local st = H.readByte(MSTATE)
  if a ~= sabinSlot then
    -- A bystander standing in a list window is backed out of it before the
    -- command walk means anything (an A press there confirms a row).
    if st == ST_TGT then
      H.setPad(ph % 8 < 4 and { a = true } or {})   -- a swing needs a target
      return
    end
    if st ~= ST_CMD then
      H.setPad(ph % 8 < 4 and { b = true } or {})
      return
    end
    local cur = H.readByte(0x890F + a) & 3
    local sub = ph % 40
    local denied, hurt = sabinDenied(), partyHurt()
    if denied or hurt then
      local why = denied and "sabin has lost his window" or "the party is hurt"
      if why ~= swingSaid then
        swingSaid = why
        local s1, s2 = sabinStatus()
        H.log(string.format("[swing f%d] bystanders swing: %s (sabin st1=%02x "
          .. "st2=%02x, pool %d)", H.frame, why, s1, s2, pool()))
      end
      -- swing: row 0, with `left` putting Fight back in a row a previous
      -- Defend swapped to Def. (battle_kitrefuse's walk)
      if cur ~= 0 then H.setPad(sub < 4 and { up = true } or {})
      elseif sub < 4 then H.setPad({ left = true })
      elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
      else H.setPad({}) end
      return
    end
    swingSaid = nil
    if sub < 4 then H.setPad({ right = true })       -- Fight row -> Def.
    elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local wantBlitz, hold
  if mode == "open" then
    wantBlitz, hold = cheap, true
  else
    wantBlitz = planCast(pool())
    if wantBlitz == nil then
      if not inBand(pool()) then
        -- planCast never casts the pool below the cheap row (cMax >= 2*cMin,
        -- asserted at boot), so this is a drain from outside the plan or a
        -- wrong plan; either way no cast can reach the band now
        error(string.format("PRECONDITION: Sabin's pool %d is below the cheap "
          .. "blitz (%d), so the band [%d,%d] is out of reach", pool(),
          costOf(cheap), costOf(cheap), costOf(dear) - 1), 0)
      end
      wantBlitz, hold = cheap, true
    end
  end
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
    if hold then H.setPad({}) return end
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

-- Sabin's own blitz list, up and held, at one of his real windows
local function sabinListUp()
  return H.battleLoadStarted() and H.readByte(MENU) ~= 0
     and H.readByte(ACTOR) == sabinSlot and H.readByte(MSTATE) == ST_TOOLS
end

local function openBlitzWindow(what)
  return H.repeatN(1, {
    H.call(function() mode = "open" end),
    H.driveUntil(sabinListUp, 30000, { H.call(pulse), H.waitFrames(1) }, what),
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
      "the spend plan's remainder arithmetic holds (cMax >= 2*cMin), so "
      .. "every cast leaves the pool at or above the cheap row; a repricing "
      .. "that breaks this needs a new plan, not a pin")
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

  -- 2. spend to the boundary with the blitzes themselves, and open the list
  -- at the first of Sabin's windows that finds the pool in the band.  One
  -- drive, because the pool is read where the grey is: a battle that ends
  -- between the last cast and the next window can level Sabin up, and
  -- Ot6LevelUpHeal refills his MP -- which the drive then spends again
  -- rather than opening on a pool the plan no longer holds.
  H.call(function() mode = "boundary" end),
  H.driveUntil(function() return sabinListUp() and inBand(pool()) end, 150000,
    { H.call(pulse), H.waitFrames(1) },
    "the pool is spent into the boundary and Sabin's list is up"),
  H.waitFrames(20),

  -- ... and the boundary window: grey and white side by side ----------------
  H.call(function()
    local mp = pool()
    H.log(string.format("pool after real casts: %d MP", mp))
    H.assertEq(mp >= costOf(cheap) and mp < costOf(dear), true, string.format(
      "the spend plan parked the pool in [%d,%d]: %s unaffordable, %s "
      .. "affordable -- both states on one screen",
      costOf(cheap), costOf(dear) - 1, nameText(dear), nameText(cheap)))
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
