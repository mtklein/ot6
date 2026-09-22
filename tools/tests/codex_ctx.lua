-- @suite savestate=gau_joined slow
-- codex_ctx.lua -- a battle entered from the world map after a menu save
-- selects the saved game's codex page rather than the transient page.
--
-- Ot6CodexActive picks the per-save codex page by reading $7e021f; its
-- three callers all run in battle context.
--
-- The drive:
--   0. the boot state is the mid-lifecycle control, read rather than
--      staged: the fighting run saves at every save point (the .srm
--      seed program), so gau_joined arrives at lifecycle 3 with the
--      slot-3 page populated by post-first-save fights, the transient
--      page frozen at whatever the pre-first-save opening taught, and
--      slots 1 and 2 byte-for-byte empty.  (The fled run's
--      never-saved control -- lifecycle 0, transient active -- no
--      longer exists in any chain fixture.)
--   1. stand on the Veldt at (214,149) and save into EMPTY slot 1 via
--      the real Save command, pad input only.  Ot6CodexSaveAs copies
--      the ACTIVE page (slot 3's) to the destination, so at this
--      instant slot 1 equals slot 3 and lifecycle reads 1.
--   2. fight a Veldt battle, formation staged (see "Staging" below), until
--      it teaches something through the party's real weapon classes.
--      Which formation is chosen from the fixture's own state, not named
--      here: the one the save's history left teachable (see "Choosing the
--      write formation").  Every changed byte must land in the slot-1 page
--      and none in the slot-3 or transient pages.  After this battle the
--      pages differ by exactly the earned bytes.
--   3. stage a formation holding a just-taught species, and read the seed
--      of that fresh battle before any input: the taught monster must
--      enter pre-revealed with the taught bits, which is the read half.
--      Only the slot-1 page carries those bits.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
local SAVE_SELECT = 0x14
-- codex pages (root $316000 + $400*n)
local SLOT1, SLOT2, SLOT3, TEMP = 0x316000, 0x316400, 0x316800, 0x316C00
local PAGE_USED = 0x310                 -- magic + elem@$10 + class@$190

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT = 0x05, 0x38
local CMDTBL = 0x202E

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

-- taught[species] = { elem = bits, class = bits }: what step 2 earned,
-- keyed for step 3's seed check
local taught, taughtN = {}, 0
local slot1Before, slot3Before, tempBefore = nil, nil, nil

-- Staging the Veldt's formation for the write and read battles.  The Veldt
-- deals from the list of fought formations at $1ddd: GetVeldtBattle
-- (field/battle.asm) moves its pointer $1fa5 one nonzero byte (a group of
-- eight formations) per encounter and picks inside the group with
-- UpdateBattleGrpRng, a counter at $1fa2/$1fa3.  Those counters are save
-- data, so which formations this fixture's encounters deal is fixed, and a
-- teaching formation can sit behind one start bit of eight (#244: the
-- write half met its formation at battle 8, and the read half's 40
-- encounters never dealt it again).  So both halves choose the formation,
-- always one whose bit is set in $1ddd: an exec callback on the
-- instruction after GetVeldtBattle stores its pick to $11e0 replaces the
-- pick while `staged` is set.  What is under test -- which codex page the
-- ROM writes during the battle and which page it merges at the battle's
-- seed -- is untouched: the fight, the chips, the page writes and the seed
-- merge are the ROM's.  Declared in tools/state_write_waivers.txt.
local VELDT_LIST = 0x1DDD
local FORMATIONS = H.sym("BattleMonsters") & 0x3FFFFF
local staged = nil
local function inVeldtList(f)
  return (H.readByte(VELDT_LIST + (f >> 3)) >> (f & 7)) & 1 == 1
end
local function formationAt(f)
  return H.formationRecord(function(i)
    return H.readRomByte(FORMATIONS + f * 15 + i)
  end)
end
-- does formation f open with a species step 2 taught on stage?
local function holdsTaught(f)
  local rec = formationAt(f)
  for slot = 0, 5 do
    local sp = rec.species[slot]
    if sp and (rec.present >> slot) & 1 == 1 and taught[sp] then return true end
  end
  return false
end
-- The read battle: the write formation itself when it opens with a taught
-- species (the pack the party just beat), else the first formation in the
-- Veldt list that does.  `writeF` is the write half's choice.
local function readFormation(writeF)
  if writeF ~= nil and inVeldtList(writeF) and holdsTaught(writeF) then
    return writeF
  end
  for f = 0, 511 do
    if inVeldtList(f) and holdsTaught(f) then return f end
  end
  return nil
end
do
  local gvb, hook = H.sym("GetVeldtBattle"), nil
  for a = gvb, gvb + 0x60 do             -- sta f:$0011e0 = 8F E0 11 00
    if H.readRomByte(a & 0x3FFFFF) == 0x8F
       and H.readRomByte((a + 1) & 0x3FFFFF) == 0xE0
       and H.readRomByte((a + 2) & 0x3FFFFF) == 0x11
       and H.readRomByte((a + 3) & 0x3FFFFF) == 0x00 then
      hook = a + 4; break
    end
  end
  assert(hook, "GetVeldtBattle's store to $11e0 not found")
  emu.addMemoryCallback(function()
    if staged ~= nil then
      H.log(string.format("[ctx] staged the Veldt's pick $%03X -> f%d",
        H.readWord(0x11E0) & 0x1FF, staged))
      H.writeWord(0x11E0, staged)
    end
  end, emu.callbackType.exec, hook, hook)
end

-- the in-battle action driver; 4-frame-held presses on a 5-on/5-off
-- cadence.
--
-- Teach steering: when a live monster's weak mask still has a bit some
-- party member can newly reveal, that member delivers it (Fight for a
-- weapon-class match, aimed at that monster; the Pummel list walk for the
-- blitz class, which OT6's Blitz commits with no target select, so the
-- engine picks the body), the other characters Defend, and Gau -- who has
-- no Fight row to swap into Def -- hands his window on with X; when
-- nothing present is teachable, the library's full-kit driver finishes the
-- battle (see battlePulse's modes).  All of it is read from the battle's
-- own seeded state (weak mask $3e9c+off, revealed bits $3e9d+off), so
-- nothing here pins a species id.
local ST_TOOLS = 0x30
-- The command window's side states and the transitional ones, as the
-- library's driver measured them (ot6.lua, BATTLE.ST_ROW/ST_DEF and
-- BATTLE.ST_TRANSITIONAL, plus $01 and the tools shell's $2E/$2F): RIGHT at
-- $05 walks $01 -> $27 (Def.), where A commits the defend; a B in $01 or
-- $27 cancels it.  None of the transitional states reads a button the
-- driver needs, so they get none.
local ST_ROW, ST_DEF = 0x24, 0x27
local ST_WAIT = {}
for _, st in ipairs({ 0x01, 0x02, 0x04, 0x06, 0x07, 0x09, 0x0F, 0x10, 0x26,
                      0x2E, 0x2F, 0x31, 0x32, 0x33, 0x34, 0x39, 0x3A, 0x40,
                      0x41 }) do
  ST_WAIT[st] = true
end
local CMD_FIGHT, CMD_ITEM, CMD_BLITZ = 0x00, 0x01, 0x0A
local ITEMLIST, PUMMEL, PUMMEL_COST = 0x4005, 0x5D, 4
local WEAPCLASS = H.sym("Ot6WeapClassTbl") & 0x3FFFFF
-- an ability's class byte, the scan Ot6SkillClass makes: (id, class)
-- pairs, $ff-terminated, absent = classless
local function skillClassOf(id)
  local a = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
  while H.readRomByte(a) ~= 0xFF do
    if H.readRomByte(a) == id then return H.readRomByte(a + 1) end
    a = a + 2
  end
  return 0
end
local PUMMEL_CLASS = skillClassOf(PUMMEL)
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
-- class, which needs a Fight command to swing), "blitz" (Pummel's class,
-- Ot6SkillClassTbl's $5d row, which needs the Blitz command and its 4 MP),
-- or nil
local function teachRoleOf(slot)
  if cmdCellOf(slot, CMD_FIGHT) ~= nil
     and canTeach(attackClassOf(slot)) then return "fight" end
  if cmdCellOf(slot, CMD_BLITZ) ~= nil and mpOf(slot) >= PUMMEL_COST
     and canTeach(PUMMEL_CLASS) then return "blitz" end
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

-- Choosing the write formation.  What a battle can teach the slot-1 page
-- depends on the save's history: SaveAs copies slot 3's page, so every
-- class the chain's post-save fights already revealed is known before the
-- first write battle and teaches nothing again.  A named formation is
-- luck: f57 (Stray Cat, Beakor, CrassHopper x2) taught Beakor's slash in
-- one measured run, and after the chain was regenerated on the v0.21 ROM
-- the slot-3 page already held every class bit f57's species have that this
-- party can reveal (Beakor and Stray Cat slash, CrassHopper pierce, which
-- nobody here swings), so sixteen f57 battles taught nothing.  So the
-- formation is chosen from the fixture's own state at the start of step
-- 2, and nothing about it is named here:
--   * the Veldt list $1ddd: only a formation the Veldt deals here;
--   * each present species' class-weak mask, the byte Ot6SeedShields
--     seeds into $3e9c: its Ot6ShieldTbl row (4-byte records, word
--     species, byte shields, byte classes, $ffff-ended, first match wins),
--     else OT6_FLOOR_CLASS[species];
--   * the party's teachers, fieldTeachers() below: teachRoleOf's two roles
--     read off the field records before the battle exists;
--   * the slot-1 page's class byte (and the transient page's, the other
--     control the write half's discriminator is checked against).
-- A candidate holds a species with a class bit its mask has, a teacher
-- carries, and neither slot 1 nor the transient page knows.  The pick
-- prefers a bit a Fight row can reveal (no MP to run out of), then the
-- lightest pack by MonsterProp HP (the shortest fight to survive), then
-- the lowest formation id.
local CHAR_GAU = 0x0B
local SHIELDTBL = H.sym("Ot6ShieldTbl") & 0x3FFFFF
local FLOOR_CLASS = H.sym("OT6_FLOOR_CLASS") & 0x3FFFFF
local MONPROP = H.sym("MonsterProp") & 0x3FFFFF
local function classWeakOf(sp)
  local a = SHIELDTBL
  while H.readRomWord(a) ~= 0xFFFF do
    if H.readRomWord(a) == sp then return H.readRomByte(a + 3) end
    a = a + 4
  end
  return H.readRomByte(FLOOR_CLASS + sp)
end
local function monsterHp(sp) return H.readRomWord(MONPROP + sp * 32 + 8) end
-- The driver's teachers as the battle will field them, from the field
-- records ($1600 + 37*c) of the active party's standing members:
--   * "fight": a Fight row swings the right hand ($1F, the item battle
--     loads into $3ca8) at Ot6WeapClassTbl's class (H.weaponClass: a
--     null-break weapon teaches nothing).  Not Gau: on the Veldt
--     Ot6VeldtRow rewrites his Fight row to Leap.
--   * "blitz": a Blitz row, Pummel known ($1d28 bit 0) and its MP.
-- The command build has other rewrites (a relic's Fight -> Jump, say)
-- that this does not model; every write battle checks the prediction
-- against the battle's own command table (see `predictionHeld`).
local function fieldTeachers()
  local out = {}
  local active = H.readByte(0x1A6D) & 0x07
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) == active and H.charHp(c) > 0
       and (H.charStatus1(c) & 0xC2) == 0 then
      local rec = 0x1600 + 37 * c
      local fight, blitz = false, false
      for i = 0, 3 do
        local cmd = H.readByte(rec + 0x16 + i)
        if cmd == CMD_FIGHT then fight = true end
        if cmd == CMD_BLITZ then blitz = true end
      end
      local rh = H.readByte(rec + 0x1F)
      if fight and H.readByte(rec) ~= CHAR_GAU and H.weaponClass(rh) ~= 0 then
        out[#out + 1] = { char = c, role = "fight", cls = H.weaponClass(rh),
          what = string.format("char %d Fight rh=$%02X", c, rh) }
      end
      if blitz and (H.readByte(0x1D28) & 0x01) ~= 0
         and H.charMp(c) >= PUMMEL_COST and PUMMEL_CLASS ~= 0 then
        out[#out + 1] = { char = c, role = "blitz", cls = PUMMEL_CLASS,
          what = string.format("char %d Pummel mp=%d", c, H.charMp(c)) }
      end
    end
  end
  return out
end
-- every teachable candidate, best first; each { f, sp, bits, fightBits,
-- known, hp }
local function writeCandidates(teachers)
  local teach, fightTeach = 0, 0
  for _, t in ipairs(teachers) do
    teach = teach | t.cls
    if t.role == "fight" then fightTeach = fightTeach | t.cls end
  end
  local out = {}
  for f = 0, 511 do
    if inVeldtList(f) then
      local rec, hp, best = formationAt(f), 0, nil
      for slot = 0, 5 do
        local sp = rec.species[slot]
        if sp and (rec.present >> slot) & 1 == 1 then
          hp = hp + monsterHp(sp)
          local known = sram(SLOT1 + 0x190 + sp) | sram(TEMP + 0x190 + sp)
          local bits = classWeakOf(sp) & teach & ~known
          if bits ~= 0 and (best == nil
             or (best.fightBits == 0 and bits & fightTeach ~= 0)) then
            best = { sp = sp, bits = bits, fightBits = bits & fightTeach,
                     known = sram(SLOT1 + 0x190 + sp), weak = classWeakOf(sp) }
          end
        end
      end
      if best then
        best.f, best.hp = f, hp
        out[#out + 1] = best
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.fightBits ~= 0) ~= (b.fightBits ~= 0) then return a.fightBits ~= 0 end
    if a.hp ~= b.hp then return a.hp < b.hp end
    return a.f < b.f
  end)
  return out
end
local writeChoice = nil                 -- the chosen candidate, set in step 2
-- The prediction, judged once a write battle's seed has settled
-- (judgePrediction): with the chosen species on stage and its chosen bits
-- still open, does the battle's own command table give some seated member
-- a row that teaches them (HP aside: a teacher felled early is the fight's
-- luck, not the model's error)?  true/false, or nil when the species was
-- not on stage to judge.
local predictionHeld = nil
-- Set once a battle's seed has settled (settleSeed below): the species
-- words, masks and command tables read before it can be half-written.
-- Measured: an open-menu gate ($7BCA, already nonzero as the battle loads)
-- read f21's slot 2 as weak=00 sh=0/0 beside its seeded twin in slot 3.
local seeded = false
-- Per-battle diagnostics: the [dbg] seeded-state dump, the [steer] role
-- log, and the per-battle attack-class tally.
local lastActor, mfM = nil, 0
local dbgLogged = false                 -- one [dbg] line per battle
local steerLogged = {}                  -- one [steer] line per actor per battle
local atkSeen = {}                      -- OT6_ATKCLASS writes, tallied per battle
emu.addMemoryCallback(function(_, v)
  atkSeen[v] = (atkSeen[v] or 0) + 1
end, emu.callbackType.write, 0x7e57b8, 0x7e57b8)
-- The battle runs in one of two modes, decided at every command window
-- (and between windows), never inside a submenu:
--   "teach"   a teacher stands and a live monster still has a class bit
--             it can newly reveal: that teacher Fights with the target
--             cursor steered onto the teachable monster (or Pummels, whose
--             target the engine picks: measured, force_f21_trace.log
--             f1644, a Pummel landing on slot 3's Rhodox beside slot 4's
--             teachable GreaseMonk; the teacher Pummels again next turn),
--             the bystanders Defend, and a bystander with no Fight row (Gau,
--             whose Fight row is Leap on the Veldt) hands the window on
--             with X;
--   "finish"  nothing on stage is left to teach (taught, or never
--             teachable): the library's full-kit fight driver wins the
--             battle -- items, heals, revives, tactical skills, one healer
--             -- the kit battle_gaufight hands a Veldt pack its flee cannot
--             shake.  Gau's Veldt rows are outside its repertoire, so it
--             hands his window on with X rather than Leap out of the fight.
-- Nothing here names a formation, species or character: the teacher, the
-- target and the healer are read from the battle's own tables.
local mode, finisher = "teach", nil
local chosenRole = {}                   -- the role a teacher walked into, per slot
local T = H.targetCursor()              -- monster-side cursor steer
local tapNo, tapAt = -1, 0              -- the steer's tap being pressed
local function battleReset()
  lastActor = nil
  dbgLogged = false
  steerLogged = {}
  atkSeen = {}
  predictionHeld = nil
  seeded = false
  mode, finisher, chosenRole = "teach", nil, {}
  tapNo, tapAt = -1, 0
end
-- the live monster slot this class can teach, lowest first, or nil
local function teachSlotFor(cls)
  for m = 0, 5 do
    if H.readByte(0x3aa8 + m * 2) % 2 == 1 then
      local off = 8 + m * 2
      local weak, rev = H.readByte(0x3e9c + off), H.readByte(0x3e9d + off)
      if weak & ~rev & cls ~= 0 then return m end
    end
  end
  return nil
end
-- the finisher's one healer: the last standing member with both a Fight
-- and an Item row carries the bag (the library's heal-lock guard: a party
-- whose every member heals can stop attacking)
local function healerChid()
  for s = 3, 0, -1 do
    local chid = H.readByte(0x3ED8 + s * 2)
    if chid ~= 0xFF and H.readWord(0x3BF4 + s * 2) > 0
       and cmdCellOf(s, CMD_FIGHT) ~= nil and cmdCellOf(s, CMD_ITEM) ~= nil then
      return chid
    end
  end
  return nil
end
local function walkToCell(a, cell, hold)
  local btn = "a"
  local cur = H.readByte(0x890F + a)
  if cur ~= cell then btn = (cur < cell) and "down" or "up" end
  H.setPad(hold and { [btn] = true } or {})
end
local function judgePrediction()
  local open = nil                      -- the chosen bits the seed left open
  for m = 0, 5 do
    if H.readByte(0x3aa8 + m * 2) % 2 == 1
       and H.readWord(0x57C0 + m * 2) == writeChoice.sp then
      local off = 8 + m * 2
      open = H.readByte(0x3e9c + off) & ~H.readByte(0x3e9d + off)
        & writeChoice.bits
    end
  end
  if open ~= nil then
    predictionHeld = false
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
        if cmdCellOf(s, CMD_FIGHT) ~= nil and attackClassOf(s) & open ~= 0 then
          predictionHeld = true
        end
        if cmdCellOf(s, CMD_BLITZ) ~= nil and mpOf(s) >= PUMMEL_COST
           and PUMMEL_CLASS & open ~= 0 then
          predictionHeld = true
        end
      end
    end
  end
  H.log(string.format("[ctx] seeded: species $%03X %s; a seated member's "
    .. "row can teach them: %s", writeChoice.sp,
    open == nil and "not on stage"
      or string.format("on stage with chosen bits %02X still open", open),
    tostring(predictionHeld)))
end
-- A battle's seed, settled: the monsters populate, their alive bits land,
-- then 90 frames with the pad released (the read half's settle), and only
-- then is anything read off the seeded tables.
local function settleSeed(tag)
  return H.repeatN(1, {
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.monstersPresent() > 0 end, 1200,
      tag .. ": monsters populate", 5),
    H.waitUntil(function()
      for slot = 0, 5 do
        if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then return true end
      end
      return false
    end, 900, tag .. ": alive bits seed", 5),
    H.waitFrames(90),
    H.call(function() seeded = true end),
  })
end
local fightSpecies = {}
local function battlePulse()
  if H.monstersPresent() > 0 then
    -- species and the [dbg] dump are read once the seed has settled; a
    -- word past the species range is not a species (measured: $5554 and
    -- $5958 turn up in alive slots even after the settle) and is dropped
    local anyAlive = false
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
        anyAlive = true
        local sp = H.readWord(0x57C0 + s * 2)
        if seeded and sp < 0x180 then fightSpecies[sp] = true end
      end
    end
    if anyAlive and not dbgLogged and seeded then
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
  T.observe()
  local menu, st = H.readByte(MENU), H.readByte(MSTATE)
  if st ~= ST_TGT then tapNo = -1 end
  if menu == 0 or st == ST_CMD then
    local present = teacherPresent()
    local want = present and "teach" or "finish"
    if want ~= mode then
      H.log(string.format("[ctx] battle mode %s -> %s", mode, want))
      mode = want
    end
  end
  if mode == "finish" then
    if finisher == nil then
      local healer = healerChid()
      H.log(string.format("[ctx] finishing with the full kit, healer chid %s",
        healer and string.format("%02X", healer) or "none (everyone)"))
      finisher = H.newFightDriver("codex-finish",
        { items = true, tactical = true, healer = healer })
    end
    finisher.frame()
    return
  end
  if menu == 0 then
    lastActor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if lastActor ~= a then lastActor, mfM = a, 0 end
  mfM = mfM + 1
  local hold = (mfM % 10) < 5
  local btn = nil
  if st == ST_CMD then
    -- teach steering (see the header above)
    local role = teachRoleOf(a)
    if not steerLogged[a] then
      steerLogged[a] = true
      H.log(string.format("[steer] slot %d (cls %02x): %s",
        a, attackClassOf(a), role or "step aside"))
    end
    chosenRole[a] = role
    if role == "fight" then
      walkToCell(a, cmdCellOf(a, CMD_FIGHT), hold)
    elseif role == "blitz" then
      -- walk onto the Blitz row; the ST_TOOLS branch below takes the list
      -- to Pummel
      walkToCell(a, cmdCellOf(a, CMD_BLITZ), hold)
    elseif cmdCellOf(a, CMD_FIGHT) ~= nil then
      -- a bystander with a Fight row: a real Defend, RIGHT here opens the
      -- Def. window and the ST_DEF branch below takes it with A
      H.setPad(hold and { right = true } or {})
    else
      -- no Fight row to swap into Def (Gau, whose row 0 is Leap on the
      -- Veldt): hand the window on with X, vanilla's turn-cycling key, as
      -- the library's driver does for him
      H.setPad(hold and { x = true } or {})
    end
    return
  elseif st == ST_TOOLS then
    -- the blitz teacher's list (the tools-shell submenu): walk to Pummel
    -- and confirm; anyone else backs out
    if chosenRole[a] == "blitz" then
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
  elseif st == ST_DEF then
    -- the bystander's Defend commits here; a teacher never asked for it
    btn = (chosenRole[a] == nil) and "a" or "b"
  elseif st == ST_ROW then
    btn = "b"                           -- never pressed for: back out
  elseif ST_WAIT[st] then
    H.setPad({})                        -- nothing here reads a button
    return
  elseif st == ST_TGT then
    -- a teacher's swing goes to the monster it can teach (H.targetCursor:
    -- "a" once the cursor sits there, else a tap; each decided tap is held
    -- four frames from its decision, battle_assassinate's pattern); a
    -- Pummel never comes here, its commit has no target select
    local slot = nil
    if chosenRole[a] == "fight" then slot = teachSlotFor(attackClassOf(a)) end
    if slot == nil then
      btn = "a"
    else
      btn = T.steer(slot, mfM)
      if btn ~= "a" then
        if btn ~= nil and T.press ~= tapNo then tapNo, tapAt = T.press, mfM end
        btn = (tapNo >= 0 and mfM - tapAt < 4) and T.dir or nil
        H.setPad(btn and { [btn] = true } or {})
        return
      end
    end
  else
    -- battle messages: the reveal banner blocks the queue until
    -- dismissed.  Tap B, not A -- B dismisses banners and messages just as
    -- well but can never confirm a just-opened command window's row 0.
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

  -- 0. the mid-lifecycle control, read: the fighting run saves into
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
  -- ReloadMap on menu close cannot pull the party off the overworld.  An
  -- encounter on the way is fought (M.FIGHT_NOT_FLEE turns "flee" into the
  -- tactical driver) and can only teach the ACTIVE page, slot 3's, before
  -- the save: SaveAs then copies it, so step 2's diff starts after it.
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

  -- 2. the write half: choose the formation (see "Choosing the write
  -- formation"), pace the Veldt into it, fight it, and after each battle
  -- diff both pages.  The first battle that teaches must have written the
  -- slot-1 page and only it.  The choice is the precondition: a fixture
  -- whose history left nothing teachable fails here, before any battle.
  H.call(function()
    local teachers = fieldTeachers()
    local tt = {}
    for _, t in ipairs(teachers) do
      tt[#tt + 1] = string.format("%s class %02X", t.what, t.cls)
    end
    local teacherText = #tt > 0 and table.concat(tt, ", ") or "none"
    local fought = 0
    for f = 0, 511 do if inVeldtList(f) then fought = fought + 1 end end
    local cands = writeCandidates(teachers)
    local ct = {}
    for _, c in ipairs(cands) do
      ct[#ct + 1] = string.format("f%d:$%03X/%02X/hp%d", c.f, c.sp, c.bits, c.hp)
    end
    H.log("[ctx] teachers the field records predict: " .. teacherText)
    H.log(string.format("[ctx] teachable Veldt formations, %d of %d fought, "
      .. "best first (f:species/new class bits/pack HP): %s", #cands, fought,
      #ct > 0 and table.concat(ct, " ") or "none"))
    H.assertEq(#cands > 0, true, string.format(
      "PRECONDITION: of the %d formations the Veldt deals here ($1ddd), one "
      .. "holds a species whose class-weak mask has a bit the party's "
      .. "teachers (%s) carry and neither the slot-1 page nor the transient "
      .. "page knows -- with none, no write battle can teach the slot-1 page "
      .. "anything; the fixture's history already taught all of it",
      fought, teacherText))
    writeChoice = cands[1]
    local c = writeChoice
    H.log(string.format("[ctx] write formation f%d: species $%03X is class-"
      .. "weak %02X and slot 1 knows %02X, so %02X is new (%s); pack HP %d; "
      .. "best of %d by Fight-teachable, lightest pack, lowest id",
      c.f, c.sp, c.weak, c.known, c.bits,
      c.fightBits ~= 0 and "a Fight row reveals it" or "only Pummel reveals it",
      c.hp, #cands))
  end),
  (function()
    local fights = 0
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
      -- the choice's prediction, judged at this battle's settled seed
      -- (predictionHeld): a battle that taught nothing with the species on
      -- stage and no teaching row in the battle's own tables means the
      -- field-side model disagrees with the battle's, and no retry can fix
      -- that.  A species not on stage then is not judged: retried.
      if taughtN == 0 then
        H.assertEq(predictionHeld ~= false, true, string.format(
          "write battle %d: with species $%03X on stage, the battle's command "
          .. "table and seeded masks give a member a role that can teach its "
          .. "class bits %02X, as the field records predicted", fights,
          writeChoice.sp, writeChoice.bits))
      end
      fightSpecies = {}
    end
    -- One try per encounter: heal through the field menu (Tonics first),
    -- pace until a battle loads, fight it through the real menus, and diff
    -- the pages.  Care comes first, the first try included: the Veldt
    -- serves the SAVE's recorded history, and a party walking in half-dead
    -- does not survive every pack in it (measured, an un-healed search
    -- entered its seventh fight with SABIN at 64 HP and wiped).  The formation is staged and chosen teachable, so one
    -- battle normally teaches; the bound only covers a staged battle whose
    -- teaching hit did not land.
    local function writeTry(n)
      return H.cond(function() return taughtN == 0 end, {
        H.waitUntil(function()
          return H.worldMode() and H.worldHasControl() and H.worldAligned()
        end, 2400, "world control before write-half try " .. n, 5),
        H.fieldCare({ tag = "codex write try " .. n, threshold = 0.95 }),
        H.call(function() staged = writeChoice.f end),
        H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
          H.call(patrolPulse),
        }, "find write-half encounter " .. n),
        H.call(function() staged = nil end),
        H.call(battleReset),
        settleSeed("write-half battle " .. n),
        H.call(judgePrediction),
        H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
          H.call(battlePulse),
        }, "fight write-half battle " .. n),
        H.call(account),
      }, {})
    end
    local tries = {}
    for n = 1, 16 do tries[#tries + 1] = writeTry(n) end
    return H.cond(function() return true end, tries, {})
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
  -- knowledge only the slot-1 page carries.  The formation is staged
  -- (readFormation), the seed checked, and the battle then fled (no
  -- submenu is open at seed, so a bare L+R hold releases).  Each try is a
  -- player-shaped episode: recover on the field, meet the battle,
  -- seed-check it, resolve it; the bound covers an encounter that did not
  -- load the staged formation.
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
      -- history -- the fighting run's history feeds this trio far
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
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 2400, "world control before read-half try " .. n, 5),
    H.fieldCare({ tag = "codex read try " .. n, threshold = 0.95 }),
    H.call(function()
      staged = readFormation(writeChoice and writeChoice.f)
      H.assertEq(staged ~= nil, true,
        "the Veldt list holds a formation with a species step 2 taught")
      H.log(string.format("[ctx] read formation f%d", staged))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(patrolPulse),
    }, "find read-half encounter " .. n),
    H.call(function() staged = nil end),
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
    H.call(function() battleReset(); seeded = true end),
    resolveReadBattle(n),
  }, {})
end

-- The read formation is staged, so the first try normally sees a taught
-- species; the bound only covers an encounter that did not load it.
for n = 1, 4 do actions[#actions + 1] = readTry(n) end
actions[#actions + 1] = H.call(function()
  H.assertEq(readChecked > 0, true,
    "READ HALF: at least one taught-species monster was checked at seed")
  H.log("[ctx] read half verified: the post-menu battle merged the SAVED page")
end)

H.run({ maxFrames = 300000 }, actions)
