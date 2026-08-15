-- @suite savestate=gau_joined slow
-- codex_ctx.lua -- a battle entered from the world map after a menu save
-- selects the saved game's codex page rather than the transient page
-- (issue #29).
--
-- The guarantee this pins: Ot6CodexActive (ff6/src/battle/ot6_codex.asm)
-- picks the per-save codex page by reading $7e021f, and its three callers
-- all run in battle context (ot6_break.asm:86/:849/:949).  $021f is a menu
-- module variable, so issue #29 asked whether any other module overlays it
-- between the menu's lifecycle write and the battle's read.  The 2026-07-28
-- audit measured the full module matrix (field/world/battle/menu, fresh and
-- loaded, pre- and post-menu, pre- and post-save) and found the cell held
-- the lifecycle value at every consumer read in every player-shaped flow:
-- $021f has exactly four writers, all menu lifecycle moments
-- (menu_common.asm:250, field_menu.asm:2925/:2963, save.asm:50), the world
-- module's DP swap covers only $0000-$00FF (world/init.asm:1446-1516), and
-- the menu's own clock tick stops at $021e (menu_common.asm:3494-3522, .a8).
-- The overlay measured in issue #29 (value 5, then a 36/37 oscillation) was
-- reproduced only under codex_saveas's then-forced-ZMENUSTATE save drive
-- (since converted to pad input), whose corrupted exit path left menu tasks
-- running.  It does not occur in any real flow.
--
-- The drive (issue #75 conversion: the discriminator used to be forged, with
-- fire written into all 384 slot-3 species and ice into all 384 transient
-- species, and the closing fight was ended by the monster-dead flag write.
-- Both pages' content is now produced by play, following cb8e605's
-- baseline-change approach, and the fight is fled):
--   0. the boot state is the pre-save control, read rather than staged: the
--      never-saved chain's fights populated the transient page (lifecycle
--      0 writes go there) while all three save-slot pages read
--      empty, asserted byte-for-byte.
--   1. stand on the Veldt at (214,149) and save into empty slot 3 via the
--      real Save command, pad input only (save-drive rule).  SaveAs copies
--      the transient payload, so at this instant the two pages are equal.
--   2. fight until the Veldt's varied formations teach something through
--      the party's real weapon classes.  The chip path's persistent
--      store consults Ot6CodexActive mid-battle, so the page
--      diff is the write half of the guarantee: every changed byte must
--      land in the slot-3 page and none in the transient page (lifecycle
--      3 now).  After this battle the pages differ by exactly the earned
--      bytes: knowledge slot 3 holds and the transient page lacks, asserted
--      by SRAM read.
--   3. fight again and read the seed before any input: a present monster
--      of a just-taught species must enter pre-revealed with the taught
--      bits, which is the read half.  Only the slot-3 page carries those
--      bits, so if any module had overlaid $021f between the save and this
--      battle, Ot6CodexActive would fall back to the transient page and the
--      pre-reveal would be missing.  (Species not in the taught set defer
--      the check to the next encounter, with bounded retries, fled with the
--      real run mechanic.)
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
local SAVE_SELECT = 0x14
local SLOT3, TEMP = 0x316800, 0x316C00  -- codex pages (root $316000 + $400*n)
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
local slot3Before, tempBefore = nil, nil

-- the in-battle action driver (codex_saveas's, measured): everyone Fights;
-- 4-frame-held presses on a 5-on/5-off cadence.  On gau_joined that means
-- Cyan's blade plus Sabin and Gau's bludgeoning hands, against the Veldt's
-- varied species rather than one exhausted Narshe pool.
local lastActor, mfM, actM = nil, 0, nil
-- The driver retains its Terra/Fire branch because this file shares the
-- proven menu walker, but this fixture has no Terra: every live action here
-- takes the ordinary Fight branch.
local function battleReset()
  lastActor = nil
end
local fightSpecies = {}
local function battlePulse()
  if H.monstersPresent() > 0 then
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
        fightSpecies[H.readWord(0x57C0 + s * 2)] = true
      end
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
    -- transitional states and battle messages (the reveal banner blocks
    -- the queue until dismissed; measured: st=$01 held for 30000 frames
    -- with no press): tap A through them
    btn = "a"
  end
  H.setPad((hold and btn) and { [btn] = true } or {})
end

-- gen_sabin_gau's proven Veldt pacing: alternate left/right at tile
-- boundaries.  North from this fixture is a map entrance, so a generic
-- four-direction beat can legitimately leave the overworld.
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
  veldtFlip = not veldtFlip
  H.setPad({ [veldtFlip and "left" or "right"] = true })
end

local actions = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),

  -- 0. the pre-save control, read: lifecycle-0 fights taught the transient
  -- page and only it.  (The forged all-species staging this replaces could
  -- not fail; these reads can.)
  H.call(function()
    H.assertEq(H.readByte(0x021f), 0, "never-saved chain: lifecycle reads 0")
    H.assertEq(sram(TEMP), 0x4f, "transient codex magic 'O'")
    H.assertEq(sram(TEMP + 1), 0x38, "transient codex magic '8'")
    local known = 0
    for off = 0x10, PAGE_USED - 1 do
      if sram(TEMP + off) ~= 0 then known = known + 1 end
    end
    H.assertEq(known > 0, true,
      "control: the chain's lifecycle-0 fights populated the TRANSIENT page")
    for _, base in ipairs({ 0x316000, 0x316400, SLOT3 }) do
      for off = 0, PAGE_USED - 1 do
        H.assertEq(sram(base + off), 0, string.format(
          "...and never touched save-slot page $%06X (+%03X)", base, off))
      end
    end
    H.log(string.format("[ctx] boot control: %d transient byte(s), slots empty",
      known))
  end),

  -- Park on the fixture's plain Veldt tile.  It is not a town entrance, so
  -- ReloadMap on menu close cannot pull the party off the overworld.
  -- issue #75: this walk really can be interrupted -- the note above
  -- records a desert fight popping ~300 frames out of the old Figaro park
  -- -- and it used to be the library's flag write that ended it.  Fled
  -- rather than fought, because a fought battle chips shields and a chip is
  -- exactly what this test's discriminator is made of: an incidental win
  -- here would teach the transient page before the save copies it, and
  -- muddy the page diff step 2 asserts.  A fled battle teaches nothing.
  H.worldNavTo(214, 149, { maxFrames = 15000, playBattles = "flee" }),

  -- 1. save into slot 3, pad input only (save-drive rule; the cursor is
  -- read back, never written).
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
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function() return sram(0x307ff0) == 3 end, 900, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 3"),
  H.call(function()
    H.assertEq(sram(0x307ff0), 3, "SRAM last-saved-slot marker is 3")
    H.assertEq(sram(SLOT3), 0x4f, "slot 3 codex magic 'O'")
    H.assertEq(sram(SLOT3 + 1), 0x38, "slot 3 codex magic '8'")
    -- SaveAs copied the transient payload, so the pages are equal right now,
    -- and any later divergence is a post-save codex write, attributable to a
    -- page
    for off = 0x10, PAGE_USED - 1 do
      H.assertEq(sram(SLOT3 + off), sram(TEMP + off),
        "SaveAs left the pages equal at " .. offName(off))
    end
    slot3Before, tempBefore = snapPage(SLOT3), snapPage(TEMP)
  end),

  -- Close the menu.  worldReady() and worldHasControl() read menu-module
  -- garbage while the menu owns the zero page (measured), so the positive
  -- check that the world module is back is the exact parked tile.
  H.driveUntil(function()
    return H.worldMode() and H.worldAligned() and bright() >= 15
       and H.worldX() == 214 and H.worldY() == 149
  end, 4000, {
    H.pressButtons({ "b" }, 4), H.waitFrames(20),
  }, "world control after menu close"),

  -- 2. the write half: pace the Veldt, fight whatever
  -- interrupts, and after each battle diff both pages.  The first battle that
  -- teaches must have written the slot-3 page and only it.  (Desert
  -- encounters teach nothing to this kit, the loop keeps walking.)
  -- This is one single-call state machine: H.cond latches its branch on the
  -- first tick inside a driveUntil body (measured: the branch chosen on frame
  -- one replayed for the whole loop and the battle accounting never ran), so
  -- the battle edge is detected inline instead.
  (function()
    local fights, wasInBattle = 0, false
    local function account()
      fights = fights + 1
      for off = 0x10, PAGE_USED - 1 do
        local s3, tp = sram(SLOT3 + off), sram(TEMP + off)
        if s3 ~= slot3Before[off] then
          local sp = (off >= 0x190) and (off - 0x190) or (off - 0x10)
          local kind = (off >= 0x190) and "class" or "elem"
          taught[sp] = taught[sp] or { elem = 0, class = 0 }
          taught[sp][kind] = taught[sp][kind] | (s3 ~ slot3Before[off])
          taughtN = taughtN + 1
          H.log(string.format("[ctx] post-save teach -> SLOT 3: %s %02X -> %02X",
            offName(off), slot3Before[off], s3))
        end
        H.assertEq(tp, tempBefore[off],
          "the post-save battle wrote NOTHING to the transient page (" ..
          offName(off) .. ")")
      end
      slot3Before = snapPage(SLOT3)
      local sp = {}
      for k in pairs(fightSpecies) do sp[#sp + 1] = string.format("%04X", k) end
      H.log(string.format("[ctx] battle %d done, taught %d byte(s) so far " ..
        "(species %s)", fights, taughtN, table.concat(sp, " ")))
      fightSpecies = {}
    end
    return H.driveUntil(function()
      return (taughtN > 0 or fights >= 6) and not H.battleLoadStarted()
    end, 40000, {
      H.call(function()
        local inBattle = H.battleLoadStarted()
        if wasInBattle and not inBattle then account() end
        if inBattle and not wasInBattle then battleReset() end
        wasInBattle = inBattle
        if inBattle then battlePulse() else patrolPulse() end
      end),
    }, "a post-save battle teaches the slot-3 page")
  end)(),
  H.call(function()
    H.assertEq(taughtN > 0, true,
      "WRITE HALF: a post-save chip landed in the SLOT-3 codex page " ..
      "(Ot6CodexActive honored the saved lifecycle mid-battle)")
    -- the discriminator exists: bits slot 3 holds that the transient lacks
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
  -- knowledge only the slot-3 page carries.  Encounters without a taught
  -- species are fled (1914283's idiom; no submenu is open at seed, so a
  -- bare L+R hold releases) and retried, with a bound on the retries.
  -- The Veldt advances through its formation table rather than immediately
  -- repeating the fight that taught the discriminator.  Search it as a
  -- sequence of player-shaped episodes: seed-check one battle, resolve it,
  -- then recover on the field before looking for the next.  Besides keeping
  -- the party alive through unrunnable set pieces, the explicit field-care
  -- boundary proves that ordinary menu use does not disturb lifecycle 3.
}

local readChecked, readTries = 0, 0

local function checkReadSeed()
  readTries = readTries + 1
  local n = 0
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
            "with the post-save elem bits -- only the slot-3 page holds them",
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
      -- Ordinary runnable formations release quickly.  If this is one of the
      -- Veldt's unrunnable set pieces, stop donating HP to a futile escape
      -- after ten seconds and win it through the real battle menus instead.
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

for n = 1, 20 do actions[#actions + 1] = readTry(n) end
actions[#actions + 1] = H.call(function()
  H.assertEq(readChecked > 0, true,
    "READ HALF: at least one taught-species monster was checked at seed")
  H.log("[ctx] read half verified: the post-menu battle merged the SAVED page")
end)

H.run({ maxFrames = 300000 }, actions)
