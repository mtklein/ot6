-- @suite savestate=worldmap_narshe slow
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
-- species, and the closing fight was ended with the kill bit.  Both pages'
-- content is now produced by play, following cb8e605's baseline-change
-- approach, and the fight is fled):
--   0. the boot state is the pre-save control, read rather than staged: the
--      never-saved chain's fights populated the transient page (lifecycle
--      0 writes go there) while all three save-slot pages read
--      empty, asserted byte-for-byte.
--   1. walk onto the grass area (82,52) and save into empty slot 3 via the
--      real Save command, pad input only (save-drive rule).  SaveAs copies
--      the transient payload, so at this instant the two pages are equal.
--   2. walk back into the grass area and fight until a battle teaches
--      something (Terra's real Fire on the pool's fire-weak staple, species
--      $17, measured weak $81 with 2 shields).  The chip path's persistent
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
local STATE = "build/states/worldmap_narshe.mss.lua"

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

-- the in-battle action driver (codex_saveas's, measured): TERRA casts
-- Fire through the live magic menu, everyone else Fights; 4-frame-held
-- presses on a 5-on/5-off cadence
local lastActor, mfM, actM = nil, 0, nil
-- TERRA's cast is the only teach this kit has in the fire-weak area, and
-- it only lands reliably in the first battle after a stretch of world
-- control, measured across five drive variants: in back-to-back
-- battles her window sits in the queue-wait state $01 for whole fights
-- (X-defers, committed Defends, and a fully parked partner all measured
-- worse), while battle one of every timeline casts within
-- two turns.  So the route below is arranged to make the first
-- post-save encounter a grass one, and the driver stays simple.
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

-- a world patrol beat along the Narshe to Figaro corridor (the
-- fixture nav's own waypoints: x=82 from the grass area down to the
-- desert edge).  A goal that cannot be planned rotates to the next, so
-- an unreachable point stalls nothing.
-- the grass area's two-point beat along the corridor column x=82 (the
-- fixture nav's own waypoints)
local GOALS = { { 82, 44 }, { 82, 60 } }
local plan, planIdx, goalI = nil, 1, 1
local hbP = -600
local function patrolPulse()
  if H.frame - hbP >= 600 then
    hbP = H.frame
    H.log(string.format("[patrol f%d] mode=%s ctl=%s aligned=%s at (%d,%d) " ..
      "goal=%d plan=%s", H.frame, tostring(H.worldMode()),
      tostring(H.worldHasControl()), tostring(H.worldAligned()),
      H.worldX(), H.worldY(), goalI, plan and #plan or "nil"))
  end
  if not H.worldMode() then H.setPad({}); return end
  if not H.worldHasControl() then plan = nil; H.setPad({}); return end
  if not H.worldAligned() then return end
  if not plan or planIdx > #plan then
    local g = GOALS[goalI]
    if H.worldX() == g[1] and H.worldY() == g[2] then
      goalI = (goalI % #GOALS) + 1
      g = GOALS[goalI]
    end
    plan = H.worldBfs(g[1], g[2]); planIdx = 1
    if not plan or #plan == 0 then
      plan = nil
      goalI = (goalI % #GOALS) + 1
      H.setPad({})
      return
    end
  end
  local dir = plan[planIdx]; planIdx = planIdx + 1
  if not dir then H.setPad({}); return end
  H.setPad({ [dir] = true })
end

H.run({ maxFrames = 90000 }, {
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

  -- Park on the grass area, off the Narshe entrance tile: closing a world
  -- menu ends in ReloadMap, which re-fires the entrance under the party's
  -- feet (measured: closing on the fixture tile dropped the party into a
  -- town), so the save happens on a plain corridor tile.  Grass rather
  -- than the old Figaro park because the first post-save encounter must
  -- be a teachable one (see the drive note above): from Figaro the nav's
  -- accrued danger popped a desert fight ~300 frames out, and that pool
  -- (species $5C/$5D, weak $8A, slash-only class rows) cannot be taught
  -- by fire and pierce, measured across two timelines.
  -- issue #75: this walk really can be interrupted -- the note above
  -- records a desert fight popping ~300 frames out of the old Figaro park
  -- -- and it used to be the library's flag write that ended it.  Fled
  -- rather than fought, because a fought battle chips shields and a chip is
  -- exactly what this test's discriminator is made of: an incidental win
  -- here would teach the transient page before the save copies it, and
  -- muddy the page diff step 2 asserts.  A fled battle teaches nothing.
  H.worldNavTo(82, 52, { maxFrames = 15000, playBattles = "flee" }),

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
       and H.worldX() == 82 and H.worldY() == 52
  end, 4000, {
    H.pressButtons({ "b" }, 4), H.waitFrames(20),
  }, "world control after menu close"),

  -- 2. the write half: walk back toward the grass area, fight whatever
  -- interrupts, and after each battle diff both pages.  The first battle that
  -- teaches must have written the slot-3 page and only it.  (Desert
  -- encounters on the way teach nothing to this kit; measured: species
  -- $5C/$5D are weak $8A and slash, while Terra has fire and Locke pierce,
  -- so the loop keeps walking.)
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
  -- Same single-call shape (H.cond latches, see above): patrol; at each
  -- encounter, sample the seed ~90 frames after the monsters populate and
  -- before any input, then flee (1914283's idiom; no submenu is open at
  -- seed, so a bare L+R hold releases); untaught pools defer to the next
  -- encounter, with a bound.
  (function()
    local tries, checked = 0, 0
    local wasIn, seedFrame, sampled = false, nil, false
    local function seedCheck()
      tries = tries + 1
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
                "with the post-save elem bits -- only the slot-3 page " ..
                "holds them", slot, sp))
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
      checked = checked + n
      H.log(string.format("[ctx] seed check try %d: %d taught monster(s) " ..
        "verified", tries, n))
    end
    return H.driveUntil(function()
      if (checked > 0 or tries >= 6) and not H.battleLoadStarted() then
        H.vars.ctxChecked = checked
        return true
      end
      return false
    end, 40000, {
      H.call(function()
        local inB = H.battleLoadStarted()
        if not inB then
          wasIn, seedFrame, sampled = false, nil, false
          patrolPulse()
          return
        end
        if not wasIn then wasIn = true end
        if not sampled then
          if seedFrame == nil and H.monstersPresent() > 0 then
            seedFrame = H.frame
          end
          if seedFrame and H.frame - seedFrame >= 90 then
            seedCheck()
            sampled = true
          end
          H.setPad({})
          return
        end
        H.setPad({ l = true, r = true })   -- flee out, checked or not
      end),
    }, "a seeded battle surfaces the slot-3 page")
  end)(),
  H.call(function()
    H.assertEq((H.vars.ctxChecked or 0) > 0, true,
      "READ HALF: at least one taught-species monster was checked at seed")
    H.log("[ctx] read half verified: the post-menu battle merged the SAVED page")
  end),
})
