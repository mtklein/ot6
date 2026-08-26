-- @suite savestate=vargas_entry slow
-- battle_vargas.lua -- Vargas's break gauge test.  Boots vargas_entry.mss,
-- rides the scene into battle 66 (MOUNTAINS_EXT), and asserts:

--   1. the gauge seed: Vargas ($0103) 5/5 shields, class-weak OT6_BLUDG
--      ($04); both Ipoohs ($014D) 2/2, slash-weak.
--   2. Vargas's weak byte is $28 = poison|holy (vanilla poison only, holy
--      added by Ot6ElemAddTbl).
--   3. poison chips, and only poison does.  Edgar's Tools -> BioBlaster
--      (item $a4, attack $7d) takes a shield and reveals poison in $3E89.
--      Its negative control runs first, in the same fight: the party's
--      weapon swings are driven onto Vargas until his hp moves, and the
--      gauge is asserted untouched at that moment.
--   4. holy chips.  Sabin's AuraBolt (Blitz 1, skill $5e, element $20)
--      takes a shield and reveals holy in $3E89.
--   5. bludgeoning chips, twice.  Pummel (Blitz 0, skill $5d, OT6_BLUDG)
--      takes two shields, 3 -> 1, and reveals class $04: Pummel hits twice
--      (Ot6HitCountTbl), each hit its own gauge write.
--   6. the fight ends to the script.  Vargas's reaction script answers
--      `if_attack PUMMEL` with `battle_event $09 / kill_monsters ALL,
--      FADE_HORIZONTAL`, asserted by the battle tearing down within a
--      bounded window of the Pummel that caused it.

-- BioBlaster's targeting byte is $6a = ONE_SIDE|INIT_GROUP|MULTI_TARGET|
-- ENEMY without $01 MANUAL, so it aims at monster group A (the two Ipoohs)
-- until no live monster is left in it, then at Vargas.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/vargas_entry.mss.lua"

local VARGAS, IPOOH = 0x0103, 0x014D
local OT6_BLUDG, OT6_SLASH = 0x04, 0x01
local HOLY, POISON = 0x20, 0x08
local PUMMEL, AURABOLT = 0x5D, 0x5E
local BIOBLASTER, BIO_ATK = 0xA4, 0x7D  -- item id -> the attack it resolves to
local BIO_MP = 8                        -- BioBlaster's MP cost (Ot6AbilityCostTbl)
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC = 0x00, 0x01, 0x02
local CMD_TOOLS = 0x09                  -- battle command id
local CMD_BLITZ = 0x0A                  -- blitz command id
local SABIN_E = 3                       -- entity index SABIN joins into
local EDGAR_E = 0                       -- entity index EDGAR holds (asserted)
local TERRA_E = 2                       -- entity index TERRA holds
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD   = 0x05                   -- the command list, cursor live
local ST_ITEM  = 0x0A                   -- the item list
local ST_MAGIC = 0x0E                   -- the magic list
local ST_TOOLS = 0x30                   -- UpdateMenuState_30, the tools/blitz list
local ST_TGT   = 0x38                   -- UpdateMenuState_38, target select
local CMDTBL   = 0x202E                 -- in-battle commands, slot*12 + i*3
local ITEMLIST = 0x4005                 -- wItemList (btlgfx_ram.inc:36), 3/entry
local BATTINV  = 0x2686                 -- battle inventory, 5 bytes/entry
local MONMASK  = 0x7B7E                 -- monster target mask (key_target_2)
local POTION, TONIC = 0xE9, 0xE8
local CURE_ID = 0x2D
-- packed per-character battle spell lists: $2092 + ptr[slot] + idx*4
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

-- monster slot s -> entity offset 8 + 2s (battle_class's map)
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function mp(e) return H.readWord(0x3C08 + e * 2) end
local function bp(e) return H.readByte(0x3E9C + e * 2) end
local function pend(e) return H.readByte(0x3E9D + e * 2) end
local function alive(e) return hp(e) > 0 end

local aPh = 0
local spells, shWrites = {}, {}
local vSlot = 0
local vHp0 = 0                          -- Vargas's seed hp, for the control
local edgarCmds = {}                    -- read at seed, asserted, never written
local toolTurns, nudges, tgtMask = 0, 0, nil
local bioEntry = nil                    -- where the tools list rendered the tool
local pummelVhp = nil                   -- Vargas's real hp when Pummel confirmed

local function itemSlot(id)
  for i = 0, 15 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function spellIndexOf(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end
local healBusy = {}                     -- target -> frame a heal was queued
local function needsHeal(thresh)
  local best, bestR = nil, 1.0
  for e = 0, 2 do
    if alive(e) and maxhp(e) > 0 then
      local r = hp(e) / maxhp(e)
      if r < thresh and r < bestR
         and (not healBusy[e] or H.frame - healBusy[e] > 900) then
        best, bestR = e, r
      end
    end
  end
  return best
end
local function hpLine()
  local s = ""
  for e = 0, 3 do
    s = s .. string.format(" e%d=%d/%d(b%d,%dmp)", e, hp(e), maxhp(e),
      bp(e), mp(e))
  end
  return s .. string.format(" V=%d", H.readWord(MHP(vSlot)))
end

-- Liveness: present bit $3AA8 bit0 and no death/disappear bit in status-1
-- $3EEC (a killed Ipooh keeps its presence bit).
local function monsterAlive(s)
  return (H.readByte(0x3AA8 + s * 2) & 0x01) == 1
     and (H.readByte(0x3EEC + s * 2) & 0xC2) == 0
end
local function ipoohsDown()
  for s = 0, 5 do
    if s ~= vSlot and H.readWord(0x57C0 + s * 2) == IPOOH and monsterAlive(s) then
      return false
    end
  end
  return true
end

local function shields() return H.readByte(SH(vSlot)) end
local function snap(t)
  H.log(string.format("[%s] f%d actor=%d mstate=$%02X vHP=%d shields=%d/%d " ..
    "revElem=$%02X revClass=$%02X weakElem=$%02X lastSkill=$%02X",
    t, H.frame, H.readByte(ACTOR), H.readByte(MSTATE), H.readWord(MHP(vSlot)),
    shields(), H.readByte(SMX(vSlot)), H.readByte(RVE(vSlot)),
    H.readByte(RVC(vSlot)), H.readByte(WKE(vSlot)), H.readByte(0x3410)))
end

local function tapUnlessSabin()
  aPh = (aPh + 1) % 8
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then
    H.setPad({})
  else
    H.setPad(aPh < 4 and { "a" } or {})
  end
end

-- ------------------------------------------------- the per-menu driver --
-- `mode` selects the action each actor's menu drives: control (Fight, with
-- Potion under 30% / Cure under 60% emergency heals), bio (EDGAR casts
-- BioBlaster once), grind (as control, until Vargas's phase-2 script
-- fires), aurabolt/pummel (SABIN casts that Blitz once), and hold
-- (everyone hands off).  One input pulse per frame while a menu is up; a
-- watchdog backs out with B and falls back to Fight, counting a nudge.
local mode = "control"
local bioFired, blitzFired = false, false
local pressKind, pressName = nil, nil    -- a proof action's confirm is in flight
local M = {}
local function resetM()
  M.actor, M.n, M.plan, M.via, M.d = nil, 0, nil, nil, 0
  M.lastCur, M.dirI, M.tgtN = nil, nil, 0
end
resetM()

local function latchSubmit()
  if pressKind == "bio" then
    bioFired = true
  elseif pressKind == "blitz" then
    blitzFired = true
    H.log(string.format("[vargas] %s confirmed by f%d, V=%d",
      pressName or "?", H.frame, pummelVhp or -1))
  end
  pressKind = nil
end

local function decidePlan(a)
  if a == SABIN_E then
    if mode == "aurabolt" and not blitzFired then
      return { kind = "blitz", skill = AURABOLT, name = "AURABOLT" }
    end
    if mode == "pummel" and not blitzFired then
      return { kind = "blitz", skill = PUMMEL, name = "PUMMEL" }
    end
    return { kind = "wait" }
  end
  if mode == "hold" then return { kind = "wait" } end
  if mode == "bio" and a == EDGAR_E and not bioFired then
    return { kind = "bio" }
  end
  local emerg = needsHeal(0.30)
  if emerg then
    local slot = itemSlot(POTION) or itemSlot(TONIC)
    if slot then return { kind = "potion", target = emerg, slot = slot } end
  end
  if a == TERRA_E and mp(TERRA_E) >= 10 then
    local t = needsHeal(0.60)
    if t then return { kind = "cure", target = t } end
  end
  return { kind = "fight" }
end

local function pulse()
  local a = H.readByte(ACTOR)
  if M.actor ~= a then
    latchSubmit()
    resetM()
    M.actor, M.plan = a, decidePlan(a)
    if M.plan.kind ~= "fight" and M.plan.kind ~= "wait" then
      H.log(string.format("[vargas plan f%d] actor=%d %s |%s",
        H.frame, a, M.plan.kind, hpLine()))
    end
  end
  if M.plan.kind == "wait" then return {} end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  if M.n > 1200 then                     -- wedge watchdog: back out, Fight
    H.log(string.format("[vargas wd f%d] actor=%d st=%02X plan=%s",
      H.frame, a, st, M.plan.kind))
    if M.plan.kind == "bio" or M.plan.kind == "blitz" then
      nudges = nudges + 1
    end
    pressKind = nil                      -- a backed-out confirm never latches
    M.n, M.via, M.d = 0, nil, 0
    M.plan = { kind = "fight" }
    return { "b" }
  end
  if st == ST_CMD then
    M.via = nil
    local wantCmd = CMD_FIGHT
    if M.plan.kind == "potion" then wantCmd = CMD_ITEM end
    if M.plan.kind == "cure" then wantCmd = CMD_MAGIC end
    if M.plan.kind == "bio" then wantCmd = CMD_TOOLS end
    if M.plan.kind == "blitz" then wantCmd = CMD_BLITZ end
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == wantCmd then wantCell = i end
    end
    if wantCell == nil then M.plan = { kind = "fight" }; wantCell = 0 end
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then
      if M.plan.kind == "fight" then
        local want = math.min(bp(a), 3)
        if pend(a) < want then return (ph < 5) and { "r" } or {} end
      end
      return (ph < 5) and { "a" } or {}
    end
    -- move the command cursor; a direction that moves nothing
    -- rotates to the next, so the window's d-pad behaviour is never
    -- assumed
    local DIRS = { "down", "up", "left", "right" }
    if ph == 0 then
      if M.lastCur == cur then M.dirI = ((M.dirI or 0) % 4) + 1
      else M.dirI = M.dirI or 1 end
      M.lastCur = cur
    end
    return (ph < 5) and { DIRS[M.dirI or 1] } or {}
  end
  if st == ST_ITEM then
    M.d = 0
    if M.plan.kind ~= "potion" then return (ph < 5) and { "b" } or {} end
    M.via = "item"
    local cr = H.readByte(0x894F)
    if cr ~= M.plan.slot then
      return (ph < 5) and { (cr < M.plan.slot) and "down" or "up" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_MAGIC then
    M.d = 0
    if M.plan.kind ~= "cure" then return (ph < 5) and { "b" } or {} end
    M.via = "magic"
    local idx = spellIndexOf(a, CURE_ID)
    if idx == nil then
      M.plan = { kind = "fight" }
      return (ph < 5) and { "b" } or {}
    end
    local wantRow, wantCol = idx // 2, idx % 2
    local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
    local col = H.readByte(0x8917 + a)
    if absRow ~= wantRow then
      return (ph < 5) and { (absRow < wantRow) and "down" or "up" } or {}
    end
    if col ~= wantCol then
      return (ph < 5) and { (col < wantCol) and "right" or "left" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TOOLS then
    M.d = 0
    if M.plan.kind ~= "bio" and M.plan.kind ~= "blitz" then
      return (ph < 5) and { "b" } or {}
    end
    local wantId = (M.plan.kind == "bio") and BIOBLASTER or M.plan.skill
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == wantId then entry = i end
    end
    if entry == nil then return {} end   -- list still building
    if M.via ~= "toolshell" then
      M.via = "toolshell"
      if M.plan.kind == "bio" then
        toolTurns = toolTurns + 1
        bioEntry = entry
        H.log(string.format("[vargas] BioBlaster rendered at tools entry %d",
          entry))
      else
        H.log(string.format("[vargas] %s rendered at blitz entry %d",
          M.plan.name, entry))
        snap(M.plan.name .. " window")
      end
    end
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then return (ph < 5) and { (cr < row) and "down" or "up" } or {} end
    if cc ~= col then return (ph < 5) and { (cc < col) and "right" or "left" } or {} end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TGT then
    if M.plan.kind == "potion" or M.plan.kind == "cure" then
      if M.via ~= "item" and M.via ~= "magic" then
        return (ph < 5) and { "b" } or {}   -- reached via a stray Fight
      end
      local want = 1 << M.plan.target
      if H.readByte(MONMASK) ~= 0 then
        return (ph < 5) and { "left" } or {}
      end
      if H.readByte(0x7B7D) ~= want then
        M.d = M.d + 1
        if M.d > 40 then                    -- take whoever is under it
          healBusy[M.plan.target] = H.frame
          return (ph < 5) and { "a" } or {}
        end
        return (ph < 5) and { "down" } or {}
      end
      healBusy[M.plan.target] = H.frame
      return (ph < 5) and { "a" } or {}
    end
    if M.plan.kind == "bio" or M.plan.kind == "blitz" then
      if M.via ~= "toolshell" then return (ph < 5) and { "b" } or {} end
      -- edge-press A until the window closes; latchSubmit() makes the
      -- action single-shot
      M.tgtN = M.tgtN + 1
      if M.tgtN == 1 and M.plan.kind == "bio" then
        tgtMask = H.readByte(MONMASK)     -- what the engine aimed, recorded
        H.log(string.format("[vargas] tool target mask $%02X", tgtMask))
      end
      pressKind, pressName = M.plan.kind, M.plan.name
      pummelVhp = H.readWord(MHP(vSlot))  -- his real hp as of the confirm
      return (ph < 5) and { "a" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  return {}                              -- transient open/close: hands off
end

-- the one driver every proof shares: page dialogs when no menu is up,
-- otherwise let the driver act under the current mode
local hb = -600
local function fightDriver()
  return H.call(function()
    if H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("[vargas f%d %s]%s", H.frame, mode, hpLine()))
    end
    if H.readByte(MENU) == 0 then
      latchSubmit()
      resetM()
      H.setPad(H.frame % 8 < 4 and { "a" } or {})
      return
    end
    H.setPad(pulse())
  end)
end

local nBefore = 0                       -- gauge-write count before a chip

H.run({ maxFrames = 150000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "booted on map 98, VARGAS's ledge")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing him")
  end),

  -- one interaction -> the scene -> battle 66
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the VARGAS scene reaches battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),

  -- ===================================================================== --
  -- 1 + 2: the seed.  Read before anything is pressed.
  -- ===================================================================== --
  H.call(function()
    local w = {}
    for s = 0, 5 do w[s] = H.readWord(0x57C0 + s * 2) end
    H.log(string.format("formation %04X %04X %04X %04X %04X %04X",
      w[0], w[1], w[2], w[3], w[4], w[5]))
    vSlot = nil
    for s = 0, 5 do if w[s] == VARGAS then vSlot = s end end
    H.assertEq(vSlot ~= nil, true, "VARGAS ($0103) is in the formation")
    H.assertEq(w[1], IPOOH, "an Ipooh ($014D) in slot 1")
    H.assertEq(w[2], IPOOH, "an Ipooh ($014D) in slot 2")

    -- the gauge
    H.assertEq(H.readByte(SH(vSlot)), 5, "VARGAS seeds 5 shields (Ot6ShieldTbl)")
    H.assertEq(H.readByte(SMX(vSlot)), 5, "VARGAS max shields 5")
    H.assertEq(H.readByte(WKC(vSlot)), OT6_BLUDG,
      "VARGAS class row is OT6_BLUDG ($04)")
    H.assertEq(H.readByte(RVE(vSlot)), 0, "nothing revealed yet (elements)")
    H.assertEq(H.readByte(RVC(vSlot)), 0, "nothing revealed yet (classes)")
    for _, s in ipairs({ 1, 2 }) do
      H.assertEq(H.readByte(SH(s)), 2, "Ipooh slot " .. s .. " seeds 2 shields")
      H.assertEq(H.readByte(WKC(s)), OT6_SLASH, "Ipooh slot " .. s .. " is slash-weak")
    end

    -- the element add: vanilla is poison only, and OT6 adds holy.
    local weak = H.readByte(WKE(vSlot))
    H.log(string.format("VARGAS weak elements = $%02X (vanilla $08 + add $20)", weak))
    H.assertEq(weak & POISON, POISON, "poison bit (vanilla, monster_prop +25)")
    H.assertEq(weak & HOLY, HOLY,
      "HOLY bit present -- Ot6ElemAddTbl's $0103 row applied (ot6.asm:216)")
    H.assertEq(weak, POISON | HOLY, "weak byte is exactly poison|holy")

    -- Sabin, and the level AuraBolt needs
    H.assertEq(H.readByte(0x3ED8 + SABIN_E * 2), 0x05,
      "SABIN is battle entity " .. SABIN_E)
    local lv = H.readByte(0x3B18 + SABIN_E * 2)
    H.log("SABIN joins at level " .. lv)
    H.assertEq(lv >= 6, true,
      "SABIN is level 6+ so AuraBolt is learned (got " .. lv .. ")")

    -- the battle inventory ($2686, 5 bytes/entry) is scanned for item $a4;
    -- its $40 flag is what MakeToolsList filters on.
    H.assertEq(H.readByte(0x3ED8 + EDGAR_E * 2), 0x04,
      "EDGAR is battle entity " .. EDGAR_E)
    local hasTools = false
    for i = 0, 3 do
      edgarCmds[i] = H.readByte(CMDTBL + EDGAR_E * 12 + i * 3)
      if edgarCmds[i] == CMD_TOOLS then hasTools = true end
    end
    H.log(string.format("EDGAR's commands: %02X %02X %02X %02X",
      edgarCmds[0], edgarCmds[1], edgarCmds[2], edgarCmds[3]))
    H.assertEq(hasTools, true, "EDGAR owns the Tools command ($09)")
    local bioSlot, bioFlags = nil, 0
    for i = 0, 15 do
      if H.readByte(BATTINV + i * 5) == BIOBLASTER then
        bioSlot = i
        bioFlags = H.readByte(BATTINV + i * 5 + 1)
      end
    end
    H.assertEq(bioSlot ~= nil, true,
      "a BioBlaster ($a4) is in the battle inventory (the Figaro shop buy)")
    H.log(string.format("BioBlaster at battle inventory slot %d, flags $%02X",
      bioSlot, bioFlags))
    H.assertEq(bioFlags & 0x40, 0x40,
      "and it carries the $40 tools flag MakeToolsList filters on")

    vHp0 = H.readWord(MHP(vSlot))
    snap("seed")
    H.screenshot("vargas_seed")

    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = { H.frame, v } end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    emu.addMemoryCallback(function(_, v) shWrites[#shWrites + 1] = { H.frame, v } end,
      emu.callbackType.write, 0x7E3E40 + vSlot * 2, 0x7E3E40 + vSlot * 2)
  end),

  -- ===================================================================== --
  -- 3a: negative control -- plain weapon Fights must not move the gauge.
  -- ===================================================================== --
  H.driveUntil(function()
    return ipoohsDown() and H.readWord(MHP(vSlot)) < vHp0
  end, 36000, {
    fightDriver(),
  }, "both Ipoohs down and a plain weapon hit has landed on VARGAS"),
  H.call(function()
    snap("control")
    H.log(string.format("VARGAS has taken %d damage from plain weapons",
      vHp0 - H.readWord(MHP(vSlot))))
    H.assertEq(#shWrites, 0,
      "CONTROL: plain weapon hits damaged VARGAS and did NOT touch the gauge")
    H.assertEq(shields(), 5, "the gauge still reads 5/5")
    H.assertEq(H.readByte(RVE(vSlot)), 0, "and nothing is revealed yet")
  end),

  -- ===================================================================== --
  -- 3b: poison.  Edgar, one turn later, at the same target, changes only the
  -- weapon: Tools -> BioBlaster, picked by walking the real cursors.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("EDGAR's pool before the cast: %d MP", mp(EDGAR_E)))
    H.assertEq(mp(EDGAR_E) >= BIO_MP, true,
      "EDGAR's own MP funds one BioBlaster (the old pin's real need)")
    mode = "bio"
  end),
  H.driveUntil(function()
    return #shWrites > 0
  end, 20000, {
    fightDriver(),
  }, "the BioBlaster reaches VARGAS's gauge"),
  H.call(function() mode = "hold" end),
  H.driveUntil(function()
    return H.readByte(RVE(vSlot)) & POISON == POISON
  end, 1800, {
    H.waitFrames(2),
  }, "the poison reveal commits on its damage frame"),
  H.call(function()
    snap("after BIOBLASTER")
    H.log(string.format("tool turns: %d, tools entry: %s, target mask: $%02X",
      toolTurns, tostring(bioEntry), tgtMask or 0xFF))
    H.assertEq(bioEntry ~= nil, true,
      "the BioBlaster was found in the rendered tools list (wItemList)")
    H.assertEq(nudges, 0,
      "the tools menu committed without a watchdog back-out (no quiet stall)")
    H.assertEq(tgtMask ~= nil and (tgtMask & (1 << vSlot)) ~= 0, true,
      "the engine aimed the tool at VARGAS's slot -- an Ipooh cannot have " ..
      "chipped this gauge")
    H.assertEq(H.readByte(0x3410), BIO_ATK,
      "the resolved attack was BioBlaster ($7d), not a stray Fight")
    H.assertEq(shields(), 4, "BIOBLASTER took a shield: 5 -> 4")
    H.assertEq(H.readByte(RVE(vSlot)) & POISON, POISON,
      "and REVEALED poison ($08) -- the chip went through the element path")
    H.assertEq(H.readByte(RVC(vSlot)), 0,
      "no class revealed: the BioBlaster is a classless tool " ..
      "(Ot6WeapClassTbl $a4 = $00)")
    H.screenshot("vargas_poison")
  end),

  -- ===================================================================== --
  -- Phase two: fight until VARGAS's script crosses its thresholds
  -- (battle_event $07 at hp<=10880, $08 at hp<=10368) and blows the trio
  -- offstage.
  -- ===================================================================== --
  H.call(function() mode = "grind" end),
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 60000, {
    fightDriver(),
  }, "SABIN takes the field (battle_event $07/$08 ran)"),
  H.call(function()
    mode = "hold"
    H.assertEq(H.readByte(SH(vSlot)), 4,
      "the gauge reads 4 -- phase one moved HP, and exactly one shield")
    H.assertEq(#shWrites, 1,
      "and exactly ONE gauge write in all of phase one: the BioBlaster's")
    snap("phase two")
    H.screenshot("vargas_phase2")
  end),

  -- ===================================================================== --
  -- 4: holy.  AuraBolt (Blitz 1, resolved attack id $5e) picked from the
  -- real blitz list by walking the real cursor.
  -- ===================================================================== --
  H.call(function()
    nBefore = #shWrites
    blitzFired = false
    mode = "aurabolt"
  end),
  H.driveUntil(function() return #shWrites > nBefore end, 15000, {
    fightDriver(),
  }, "AURABOLT reaches the gauge"),
  H.call(function() mode = "hold" end),
  H.driveUntil(function()
    return H.readByte(RVE(vSlot)) & HOLY == HOLY
  end, 1800, {
    H.waitFrames(2),
  }, "the holy reveal commits on its damage frame"),
  H.call(function()
    snap("after AURABOLT")
    H.assertEq(H.readByte(0x3410), AURABOLT,
      "the resolved skill was AuraBolt ($5e), not a stray Fight")
    H.assertEq(shields(), 3, "AURABOLT took a shield: 4 -> 3")
    H.assertEq(H.readByte(RVE(vSlot)) & HOLY, HOLY,
      "and REVEALED holy ($20) -- the chip went through the element path")
    H.assertEq(H.readByte(RVE(vSlot)) & POISON, POISON,
      "poison stays revealed across the holy chip")
    H.assertEq(H.readByte(RVC(vSlot)), 0,
      "no class revealed by an elemental chip")
  end),

  -- ===================================================================== --
  -- 5 + 6: bludgeoning and the finish.  Pummel (Blitz 0, attack id $5d);
  -- VARGAS answers `if_attack PUMMEL` with battle_event $09 + kill_monsters
  -- ALL.
  -- ===================================================================== --
  H.call(function()
    nBefore = #shWrites
    blitzFired = false
    mode = "pummel"
  end),
  -- Pummel hits twice (Ot6HitCountTbl x2), each hit its own gauge write.
  H.driveUntil(function() return #shWrites >= nBefore + 2 end, 15000, {
    fightDriver(),
  }, "PUMMEL's two hits both reach the gauge"),
  H.call(function() mode = "hold" end),
  H.driveUntil(function()
    return H.readByte(RVC(vSlot)) & OT6_BLUDG == OT6_BLUDG
  end, 1800, {
    H.waitFrames(2),
  }, "the bludgeoning reveal commits on its damage frame"),
  H.call(function()
    snap("after PUMMEL")
    pummelVhp = H.readWord(MHP(vSlot))
    H.assertEq(H.readByte(0x3410), PUMMEL, "the resolved skill was Pummel ($5d)")
    H.assertEq(shields(), 1, "PUMMEL took TWO shields: 3 -> 1 (x2, one chip a hit)")
    H.assertEq(#shWrites - nBefore, 2,
      "and it was two separate gauge writes, one per hit, not one write of two")
    H.assertEq(H.readByte(RVC(vSlot)) & OT6_BLUDG, OT6_BLUDG,
      "and REVEALED the bludgeoning class ($04)")
    H.assertEq(H.readByte(RVE(vSlot)), POISON | HOLY,
      "both elements stay revealed across the class chip")
  end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 9000, {
    H.call(tapUnlessSabin),
  }, "the fight ends (battle_event $09 / kill_monsters ALL)"),
  H.call(function()
    H.assertEq(H.battleLoadStarted(), false, "battle torn down after PUMMEL")
    H.log(string.format("PASSED with VARGAS at %s HP -- the script killed " ..
      "him, not the damage", tostring(pummelVhp)))
    H.log("skill writes: " .. #spells .. ", gauge writes: " .. #shWrites)
    for i = 1, #shWrites do
      H.log(string.format("  gauge f%d -> %d", shWrites[i][1], shWrites[i][2]))
    end
    H.screenshot("vargas_won")
  end),
})
