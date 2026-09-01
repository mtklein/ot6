-- @suite savestate=gau_joined slow
-- codex_ctx.lua -- a battle entered from the world map after a menu save
-- selects the saved game's codex page rather than the transient page.
--
-- Ot6CodexActive picks the per-save codex page by reading $7e021f; its
-- three callers all run in battle context.
--
-- The drive:
--   0. the boot state is the mid-lifecycle control, read rather than
--      staged: the fighting lineage saves at every save point (the .srm
--      seed program), so gau_joined arrives at lifecycle 3 with the
--      slot-3 page populated by post-first-save fights, the transient
--      page frozen at whatever the pre-first-save opening taught, and
--      slots 1 and 2 byte-for-byte empty.  (The fled lineage's
--      never-saved control -- lifecycle 0, transient active -- no
--      longer exists in any chain fixture.)
--   1. stand on the Veldt at (214,149) and save into EMPTY slot 1 via
--      the real Save command, pad input only.  Ot6CodexSaveAs copies
--      the ACTIVE page (slot 3's) to the destination, so at this
--      instant slot 1 equals slot 3 and lifecycle reads 1.
--   2. fight until the Veldt's varied formations teach something through
--      the party's real weapon classes.  Every changed byte must land in
--      the slot-1 page and none in the slot-3 or transient pages.
--      After this battle the pages differ by exactly the earned bytes.
--   3. fight again and read the seed before any input: a present monster
--      of a just-taught species must enter pre-revealed with the taught
--      bits, which is the read half.  Only the slot-1 page carries those
--      bits.  (Species not in the taught set defer the check to the next
--      encounter, with bounded retries, fled with the run mechanic.)
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
local SAVE_SELECT = 0x14
-- codex pages (root $316000 + $400*n)
local SLOT1, SLOT2, SLOT3, TEMP = 0x316000, 0x316400, 0x316800, 0x316C00
local PAGE_USED = 0x310                 -- magic + elem@$10 + class@$190

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_MAGIC, ST_TGT = 0x05, 0x0E, 0x38
local CMDTBL = 0x202E
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local FIRE = 0x00

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end
local function snapPage(base)
  local t = {}
  for off = 0, PAGE_USED - 1 do t[off] = sram(base + off) end
  return t
end
local function offName(off)
  if off >= 0x190 then return string.format("class species $%03X", off - 0x190) end
  if off >= 0x10 then return string.format("elem species $%03X", off - 0x10) end
  return string.format("header+%X", off)
end
local function spellIndexOf(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end

-- taught[species] = { elem = bits, class = bits }: what step 2 earned,
-- keyed for step 3's seed check
local taught, taughtN = {}, 0
local slot1Before, slot3Before, tempBefore = nil, nil, nil

-- the in-battle action driver: everyone Fights; 4-frame-held presses on a
-- 5-on/5-off cadence.
--
-- Teach steering: when a live monster's weak mask still has a bit some
-- party member can newly reveal, that member delivers it (Fight for a
-- weapon-class match, the Pummel list walk for the blitz class), the other
-- characters Defend, and Gau -- who has no Fight row to swap into Def --
-- burns his turn on a Tonic; when nothing present is teachable, everyone
-- taps A and the filler battle ends fast.  All of it is read from the
-- battle's own seeded state (weak mask $3e9c+off, revealed bits
-- $3e9d+off), so nothing here pins a species id.
local ST_TOOLS, ST_ITEM = 0x30, 0x0A
local CMD_FIGHT, CMD_ITEM, CMD_BLITZ = 0x00, 0x01, 0x0A
local ITEMLIST, PUMMEL, PUMMEL_COST, TONIC = 0x4005, 0x5D, 4, 0xE8
local WEAPCLASS = H.sym("Ot6WeapClassTbl") & 0x3FFFFF
local function attackClassOf(slot)
  return H.readRomByte(WEAPCLASS + H.readByte(0x3ca8 + slot * 2))
end
local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end
local function mpOf(slot) return H.readWord(0x3C08 + slot * 2) end
local function battleBagIdxOf(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id
       and H.readByte(0x2686 + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function canTeach(cls)
  for m = 0, 5 do
    if H.readByte(0x3aa8 + m * 2) % 2 == 1 then
      local off = 8 + m * 2
      local weak, rev = H.readByte(0x3e9c + off), H.readByte(0x3e9d + off)
      if weak & ~rev & cls ~= 0 then return true end
    end
  end
  return false
end
-- how this slot can still teach something present: "fight" (its weapon's
-- class, which needs a Fight command to swing), "blitz" (Pummel's $04,
-- which needs the Blitz command and its 4 MP), or nil
local function teachRoleOf(slot)
  if cmdCellOf(slot, CMD_FIGHT) ~= nil
     and canTeach(attackClassOf(slot)) then return "fight" end
  if cmdCellOf(slot, CMD_BLITZ) ~= nil and mpOf(slot) >= PUMMEL_COST
     and canTeach(0x04) then return "blitz" end
  return nil
end
local function teacherPresent()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF
       and H.readWord(0x3BF4 + s * 2) > 0
       and teachRoleOf(s) ~= nil then return true end
  end
  return false
end
-- Per-battle diagnostics: the [dbg] seeded-state dump, the [steer] role
-- log, and the per-battle attack-class tally.
local lastActor, mfM, actM = nil, 0, nil
local dbgLogged = false                 -- one [dbg] line per battle
local steerLogged = {}                  -- one [steer] line per actor per battle
local atkSeen = {}                      -- OT6_ATKCLASS writes, tallied per battle
emu.addMemoryCallback(function(_, v)
  atkSeen[v] = (atkSeen[v] or 0) + 1
end, emu.callbackType.write, 0x7e57b8, 0x7e57b8)
-- this fixture has no Terra: every live action here takes the ordinary
-- Fight branch.
local function battleReset()
  lastActor = nil
  dbgLogged = false
  steerLogged = {}
  atkSeen = {}
end
local fightSpecies = {}
local function battlePulse()
  if H.monstersPresent() > 0 then
    local anyAlive = false
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
        anyAlive = true
        fightSpecies[H.readWord(0x57C0 + s * 2)] = true
      end
    end
    if anyAlive and not dbgLogged then
      dbgLogged = true
      local t = {}
      for s = 0, 3 do
        local cmds = {}
        for i = 0, 3 do
          cmds[#cmds + 1] = string.format("%02x",
            H.readByte(CMDTBL + s * 12 + i * 3))
        end
        t[#t + 1] = string.format("c%d id=%02x hp=%d hand=%02x cls=%02x cmd=%s",
          s, H.readByte(0x3ED8 + s * 2), H.readWord(0x3BF4 + s * 2),
          H.readByte(0x3ca8 + s * 2), attackClassOf(s),
          table.concat(cmds, ","))
      end
      for m = 0, 5 do
        if H.readByte(0x3aa8 + m * 2) % 2 == 1 then
          local off = 8 + m * 2
          t[#t + 1] = string.format("m%d sp=%04x weak=%02x rev=%02x sh=%d/%d",
            m, H.readWord(0x57C0 + m * 2), H.readByte(0x3e9c + off),
            H.readByte(0x3e9d + off), H.readByte(0x3e38 + off),
            H.readByte(0x3e39 + off))
        end
      end
      H.log("[dbg] " .. table.concat(t, " | "))
    end
  end
  if H.readByte(MENU) == 0 then
    lastActor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if lastActor ~= a then
    lastActor, mfM = a, 0
    actM = (H.readByte(0x3ED8 + a * 2) == 0x00) and "fire" or "fight"
  end
  mfM = mfM + 1
  local hold = (mfM % 10) < 5
  local st, btn = H.readByte(MSTATE), nil
  if st == ST_CMD then
    -- teach steering (see the header above)
    if actM ~= "fire" and teacherPresent() then
      local role = teachRoleOf(a)
      if not steerLogged[a] then
        steerLogged[a] = true
        H.log(string.format("[steer] slot %d (cls %02x): %s",
          a, attackClassOf(a), role or "step aside"))
      end
      if role == "blitz" then
        -- the teacher: walk onto the Blitz row; the ST_TOOLS branch below
        -- takes the list to Pummel
        local cell = cmdCellOf(a, CMD_BLITZ)
        btn = "a"
        local cur = H.readByte(0x890F + a)
        if cur ~= cell then btn = (cur < cell) and "down" or "up" end
        H.setPad(hold and { [btn] = true } or {})
        return
      elseif role == nil and cmdCellOf(a, CMD_FIGHT) ~= nil then
        -- a bystander with a Fight row: real Defend (right swaps
        -- Fight->Def, then A), slow cadence so the swap settles
        local step = mfM % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
        return
      elseif role == nil then
        -- Gau: no Fight row to swap into Def, so burn the turn on a real
        -- Tonic (the ST_ITEM branch below picks it)
        local cell = cmdCellOf(a, CMD_ITEM)
        btn = "a"
        if cell ~= nil then
          local cur = H.readByte(0x890F + a)
          if cur ~= cell then btn = (cur < cell) and "down" or "up" end
        end
        H.setPad(hold and { [btn] = true } or {})
        return
      end
      -- role "fight": fall through to the plain swing below
    end
    btn = "a"
    if actM == "fire" then
      local cell = nil
      for i = 0, 3 do
        if H.readByte(CMDTBL + a * 12 + i * 3) == 0x02 then cell = i end
      end
      if cell == nil then actM = "fight"
      else
        local cur = H.readByte(0x890F + a)
        if cur ~= cell then btn = (cur < cell) and "down" or "up" end
      end
    end
  elseif st == ST_TOOLS then
    -- the blitz teacher's list (the tools-shell submenu): walk to Pummel
    -- and confirm; anyone else backs out
    if actM ~= "fire" and teachRoleOf(a) == "blitz" then
      local entry = nil
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == PUMMEL then entry = i end
      end
      if entry == nil then H.setPad({}) return end   -- list still building
      local row, col = entry // 2, entry % 2
      local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
      btn = "a"
      if cr ~= row then btn = (cr < row) and "down" or "up"
      elseif cc ~= col then btn = (cc < col) and "right" or "left" end
    else
      btn = "b"
    end
  elseif st == ST_ITEM then
    -- Gau's turn-burn: the Tonic row of the battle bag
    local want = battleBagIdxOf(TONIC)
    if want == nil then btn = "b"
    else
      local cur = H.readByte(0x8947 + a) + H.readByte(0x894F + a)
      btn = "a"
      if cur < want then btn = "down"
      elseif cur > want then btn = "up" end
    end
  elseif st == ST_MAGIC then
    if actM ~= "fire" then btn = "b"
    else
      local i = spellIndexOf(a, FIRE)
      if i == nil then actM = "fight"; btn = "b"
      else
        local wantRow, wantCol = i // 2, i % 2
        local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
        local col = H.readByte(0x8917 + a)
        btn = "a"
        if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
        elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left" end
      end
    end
  elseif st == ST_TGT then
    btn = "a"
  else
    -- transitional states and battle messages: the reveal banner blocks
    -- the queue until dismissed.  Tap B, not A -- B dismisses banners and
    -- messages just as well but can never confirm a just-opened command
    -- window's row 0.
    btn = "b"
  end
  H.setPad((hold and btn) and { [btn] = true } or {})
end

-- alternate left/right at tile boundaries.  North from this fixture is a
-- map entrance, so a generic four-direction beat can legitimately leave
-- the overworld.
local veldtFlip = false
local hbP = -600
local function patrolPulse()
  if H.frame - hbP >= 600 then
    hbP = H.frame
    H.log(string.format("[patrol f%d] mode=%s ctl=%s aligned=%s at (%d,%d) " ..
      "veldt=%s", H.frame, tostring(H.worldMode()),
      tostring(H.worldHasControl()), tostring(H.worldAligned()),
      H.worldX(), H.worldY(), tostring(veldtFlip)))
  end
  if not H.worldMode() then H.setPad({}); return end
  if not H.worldHasControl() then H.setPad({}); return end
  if not H.worldAligned() then return end
  -- Stay on the Veldt: battle re-entry drifts the beat west a tile at a
  -- time, and further west the encounters dilute the search for the taught
  -- species.  Herd the walk back into a band around the parked tile before
  -- resuming the alternating beat.
  local x = H.worldX()
  if x < 210 then H.setPad({ right = true }); return end
  if x > 220 then H.setPad({ left = true }); return end
  veldtFlip = not veldtFlip
  H.setPad({ [veldtFlip and "left" or "right"] = true })
end

local actions = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),

  -- 0. the mid-lifecycle control, read: the fighting lineage saves into
  -- slot 3 at every save point, so its post-save fights taught the
  -- slot-3 page and only it; slots 1 and 2 have never been saved.
  H.call(function()
    H.assertEq(H.readByte(0x021f), 3,
      "the chain saves as it goes: lifecycle reads 3 (the .srm seed program)")
    H.assertEq(sram(SLOT3), 0x4f, "slot-3 codex magic 'O'")
    H.assertEq(sram(SLOT3 + 1), 0x38, "slot-3 codex magic '8'")
    local known = 0
    for off = 0x10, PAGE_USED - 1 do
      if sram(SLOT3 + off) ~= 0 then known = known + 1 end
    end
    H.assertEq(known > 0, true,
      "control: the chain's post-save fights populated the SLOT-3 page")
    for _, base in ipairs({ SLOT1, SLOT2 }) do
      for off = 0, PAGE_USED - 1 do
        H.assertEq(sram(base + off), 0, string.format(
          "...and never touched unsaved slot page $%06X (+%03X)", base, off))
      end
    end
    H.log(string.format("[ctx] boot control: %d slot-3 byte(s), slots 1/2 empty",
      known))
  end),

  -- Park on the fixture's plain Veldt tile: not a town entrance, so
  -- ReloadMap on menu close cannot pull the party off the overworld.  Fled
  -- rather than fought, because a fought battle chips shields and a chip
  -- is exactly what this test's discriminator is made of: an incidental
  -- win here would teach the transient page before the save copies it and
  -- muddy the page diff step 2 asserts.
  H.worldNavTo(214, 149, { maxFrames = 15000, playBattles = "flee" }),

  -- 1. save into EMPTY slot 1, pad input only (save-drive rule; the
  -- cursor is read back, never written).  SaveAs copies the ACTIVE
  -- page -- slot 3's -- so the two pages come out equal.
  H.pressButtons({ "x" }, 4),
  H.waitFrames(120),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    300, "main menu", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 0
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "save cursor on slot 1"),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function() return sram(0x307ff0) == 1 end, 900, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 1"),
  H.call(function()
    H.assertEq(sram(0x307ff0), 1, "SRAM last-saved-slot marker is 1")
    H.assertEq(H.readByte(0x021f), 1, "lifecycle follows the save to 1")
    H.assertEq(sram(SLOT1), 0x4f, "slot 1 codex magic 'O'")
    H.assertEq(sram(SLOT1 + 1), 0x38, "slot 1 codex magic '8'")
    -- SaveAs copied the ACTIVE (slot 3) page, so the pages are equal
    -- right now, and any later divergence is a post-save codex write,
    -- attributable to a page
    for off = 0x10, PAGE_USED - 1 do
      H.assertEq(sram(SLOT1 + off), sram(SLOT3 + off),
        "SaveAs left slot 1 equal to slot 3 at " .. offName(off))
    end
    slot1Before, slot3Before, tempBefore =
      snapPage(SLOT1), snapPage(SLOT3), snapPage(TEMP)
  end),

  -- Close the menu.  worldReady() and worldHasControl() read menu-module
  -- garbage while the menu owns the zero page, so the positive check that
  -- the world module is back is the exact parked tile.
  H.driveUntil(function()
    return H.worldMode() and H.worldAligned() and bright() >= 15
       and H.worldX() == 214 and H.worldY() == 149
  end, 4000, {
    H.pressButtons({ "b" }, 4), H.waitFrames(20),
  }, "world control after menu close"),

  -- 2. the write half: pace the Veldt, fight whatever
  -- interrupts, and after each battle diff both pages.  The first battle that
  -- teaches must have written the slot-1 page and only it.  (Desert
  -- encounters teach nothing to this kit, the loop keeps walking.)
  -- This is one single-call state machine: the battle edge is detected
  -- inline, since H.cond latches its branch on the first tick inside a
  -- driveUntil body.
  (function()
    local fights, wasInBattle = 0, false
    local function account()
      fights = fights + 1
      for off = 0x10, PAGE_USED - 1 do
        local s1, s3, tp = sram(SLOT1 + off), sram(SLOT3 + off), sram(TEMP + off)
        if s1 ~= slot1Before[off] then
          local sp = (off >= 0x190) and (off - 0x190) or (off - 0x10)
          local kind = (off >= 0x190) and "class" or "elem"
          taught[sp] = taught[sp] or { elem = 0, class = 0 }
          taught[sp][kind] = taught[sp][kind] | (s1 ~ slot1Before[off])
          taughtN = taughtN + 1
          H.log(string.format("[ctx] post-save teach -> SLOT 1: %s %02X -> %02X",
            offName(off), slot1Before[off], s1))
        end
        H.assertEq(s3, slot3Before[off],
          "the post-save battle wrote NOTHING to the slot-3 page (" ..
          offName(off) .. ")")
        H.assertEq(tp, tempBefore[off],
          "the post-save battle wrote NOTHING to the transient page (" ..
          offName(off) .. ")")
      end
      slot1Before = snapPage(SLOT1)
      local sp = {}
      for k in pairs(fightSpecies) do sp[#sp + 1] = string.format("%04X", k) end
      local ac = {}
      for k, n in pairs(atkSeen) do
        ac[#ac + 1] = string.format("%02x*%d", k, n)
      end
      H.log(string.format("[ctx] battle %d done, taught %d byte(s) so far " ..
        "(species %s; atkclass %s)", fights, taughtN,
        table.concat(sp, " "), table.concat(ac, " ")))
      fightSpecies = {}
    end
    -- The bail-out follows the fixture: the teachable pairing sits fourth
    -- in the Veldt's eight-formation cycle, so one full cycle plus slack
    -- bounds the search.
    return H.driveUntil(function()
      return (taughtN > 0 or fights >= 16) and not H.battleLoadStarted()
    end, 60000, {
      H.call(function()
        local inBattle = H.battleLoadStarted()
        if wasInBattle and not inBattle then account() end
        if inBattle and not wasInBattle then battleReset() end
        wasInBattle = inBattle
        if inBattle then battlePulse() else patrolPulse() end
      end),
    }, "a post-save battle teaches the slot-1 page")
  end)(),
  H.call(function()
    H.assertEq(taughtN > 0, true,
      "WRITE HALF: a post-save chip landed in the SLOT-1 codex page " ..
      "(Ot6CodexActive honored the saved lifecycle mid-battle)")
    -- the discriminator exists: bits only slot 1 holds -- a bit slot 3
    -- already knew was copied in by SaveAs and never counts as taught,
    -- so every taught bit is provably absent from BOTH control pages
    for sp, t in pairs(taught) do
      if t.elem ~= 0 then
        H.assertEq(sram(TEMP + 0x10 + sp) & t.elem, 0, string.format(
          "transient page provably lacks the taught elem bits (species $%03X)", sp))
      end
      if t.class ~= 0 then
        H.assertEq(sram(TEMP + 0x190 + sp) & t.class, 0, string.format(
          "transient page provably lacks the taught class bits (species $%03X)", sp))
      end
    end
  end),

  -- 3. the read half: a fresh battle's seed pre-reveals the taught bits,
  -- knowledge only the slot-1 page carries.  Encounters without a taught
  -- species are fled (no submenu is open at seed, so a bare L+R hold
  -- releases) and retried, with a bound on the retries.  Searched as a
  -- sequence of player-shaped episodes: seed-check one battle, resolve it,
  -- then recover on the field before looking for the next.
}

local readChecked, readTries = 0, 0

local function checkReadSeed()
  readTries = readTries + 1
  local n = 0
  local seen = {}
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      seen[#seen + 1] = string.format("%04X", H.readWord(0x57C0 + slot * 2))
    end
  end
  H.log(string.format("[ctx] seed check try %d sees: %s", readTries,
    table.concat(seen, " ")))
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      local off = 8 + slot * 2
      local sp = H.readWord(0x57C0 + slot * 2)
      local t = taught[sp]
      if t then
        local revE = H.readByte(0x3e89 + off)
        local revC = H.readByte(0x3e9d + off)
        if t.elem ~= 0 then
          H.assertEq(revE & t.elem, t.elem, string.format(
            "monster slot %d (species $%03X) entered PRE-REVEALED " ..
            "with the post-save elem bits -- only the slot-1 page holds them",
            slot, sp))
        end
        if t.class ~= 0 then
          H.assertEq(revC & t.class, t.class, string.format(
            "monster slot %d (species $%03X) entered PRE-REVEALED " ..
            "with the post-save class bits", slot, sp))
        end
        n = n + 1
      end
    end
  end
  readChecked = readChecked + n
  H.log(string.format("[ctx] seed check try %d: %d taught monster(s) verified",
    readTries, n))
end

local function resolveReadBattle(n)
  local frames = 0
  return H.driveUntil(function() return not H.battleLoadStarted() end, 15000, {
    H.call(function()
      frames = frames + 1
      -- Life support, not play: the read half only needs ONE battle whose
      -- species is taught, and the Veldt serves the SAVE's recorded
      -- history -- the fighting lineage's history feeds this trio far
      -- harder packs than the fled control ever met (measured: a read
      -- search wiped resolving an unmatched pack).  Party HP is not a
      -- measured quantity here -- seed bits are -- so every living
      -- ally's battle HP tops to max each pulse.  Declared in
      -- state_write_waivers.txt.
      for s = 0, 3 do
        local max = H.readWord(0x3C1C + s * 2)
        if max > 0 and H.readWord(0x3BF4 + s * 2) > 0 then
          H.writeWord(0x3BF4 + s * 2, max)
        end
      end
      -- Ordinary runnable formations release quickly.  If this is one of the
      -- Veldt's unrunnable set pieces, stop holding L+R after ten seconds
      -- and win it through the real battle menus instead.
      if frames < 600 then H.setPad({ l = true, r = true })
      else battlePulse() end
    end),
  }, "resolve read-half battle " .. n)
end

local function readTry(n)
  return H.cond(function() return readChecked == 0 end, {
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(patrolPulse),
    }, "find read-half encounter " .. n),
    H.waitUntil(function() return H.monstersPresent() > 0 end, 1200,
      "read-half monsters populate " .. n, 5),
    -- wait for the alive bits the check reads, not a blind settle: the
    -- $3aa8 bits land after monstersPresent() goes positive, and a check
    -- that runs before them sees an empty battle and defers a species it
    -- was looking at
    H.waitUntil(function()
      for slot = 0, 5 do
        if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then return true end
      end
      return false
    end, 900, "read-half alive bits seed " .. n, 5),
    H.waitFrames(90),
    H.call(checkReadSeed),
    H.call(battleReset),
    resolveReadBattle(n),
    H.cond(function() return readChecked == 0 end, {
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
      end, 2400, "world control after read-half battle " .. n, 5),
      H.fieldCare({ tag = "codex read search " .. n, threshold = 0.95 }),
    }, {}),
  }, {})
end

-- The retry bound follows the fixture's draw rate for the taught species.
for n = 1, 40 do actions[#actions + 1] = readTry(n) end
actions[#actions + 1] = H.call(function()
  H.assertEq(readChecked > 0, true,
    "READ HALF: at least one taught-species monster was checked at seed")
  H.log("[ctx] read half verified: the post-menu battle merged the SAVED page")
end)

H.run({ maxFrames = 300000 }, actions)
