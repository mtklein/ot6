-- @suite savestate=fc_alcove
-- battle_procboost.lua -- what the boost multiplier (Ot6BoostDmg's x2/x4/x8)
-- does and does not reach, verb by verb, through the real menus.
--
-- The rule (ot6_boostdmg.asm header):
--   * a spell whose boost bought a tier is not multiplied: the QUEUED command
--     is magic/x-magic/lore/summon and the QUEUED attack is in Ot6FoldTbl;
--   * a weapon's own on-hit spell is not multiplied (owner ruling, v0.21):
--     the boost bought that weapon's swings, not a second boost on its cast;
--   * a Rage is not multiplied: its boost bought the coin (the queued
--     command is $10; the beast's attack runs under its own command);
--   * everything else past the command gate is.
-- The executing $b5/$b6 cannot tell these apart: a Fight's Blizzard Ice, an
-- Ice Rod used from Item and a folded Ice cast all run as command $02 with a
-- fold-table spell in $b6.
--
-- From fc_alcove (TERRA with Blizzard, LOCKE, SHADOW, EDGAR; Ice Rod,
-- MithrilKnife and Magicite in the bag): out of the alcove onto the
-- continent, pace to a random encounter (whichever 394 deals), and let the
-- bench (below: a Fenix Down, a status cure or a Potion for whoever needs
-- one, else Defend) play every window until every bank holds 3, every
-- member stands at 60% of max HP or better and every case's actor is free
-- to play its verb; snapshot only then.  (A battle the party cannot get
-- ready in -- an actor under a Mute the bag cannot lift, say -- is fought
-- out and the next encounter taken, up to MEASURE_BATTLES, derived from
-- 394's pool; past that the precondition is an error.)  Each case
-- restores that snapshot, benches the other windows until its actor's
-- opens (an actor blocked there, by a greyed row or a status, benches that
-- window too and starts at a later one), presses R three times and plays
-- the verb through its menu.
-- No state is written.  Every Ot6BoostDmg call the actor
-- makes during the action is recorded ($11b0 in and out, $b5/$b6, $3a7c/$3a7d,
-- pending, OT6_WEAPSPELL).  Asserted:
--   magic   TERRA's Fire, boosted, runs as Fire 3 and leaves unmultiplied
--   fight   TERRA's Fight: every Blizzard Ice it casts leaves unmultiplied,
--           and the swings (command $00) do too; retried, each try a
--           round later than the last, until a try casts (a 1-in-4 roll
--           per hit)
--   throw   SHADOW's MithrilKnife ($01, also Ice's id) leaves x8
--   rod     LOCKE's Ice Rod from Item (runs as Ice 2) leaves x8
--   magicite  LOCKE's Magicite from Item: the drawn esper's damage (or
--           healing) leaves x8.  Which esper answers is the item's own roll
--           over a pool decoded from the ROM (magicitePool, below).  A
--           boosted Magicite draws again past an esper the boost cannot pay
--           for (#368: power 0, a revival, or Crusader's Purifier, which
--           strikes the party too), so every try keeps one that pays, and
--           every draw it passed over pays nothing; tries go on, each a
--           round later, until one has drawn again (the redraw arm ran).
--           On a ROM without the redraw, an unpayable draw fails the case
--           (and a Crusader that wipes the party ends its branch there,
--           the snapshot restored)
--   and the Fight's swings: Ot6FightBoost raised its multi-attack count by 2
--           per pending pip ($3a70 1 -> 7 at boost 3), the positive control
--           for the swing observer the Rage row reads
-- Then from gau_joined (GAU, SABIN, CYAN on the Veldt), the same shape:
--   rage    GAU's Rage at boost 3 (tier 3: the special every turn) on EVERY
--           cell of his rage window (every rage he has learned; the window
--           lists at most eight).  The boost bought the special's certainty
--           and nothing else (owner ruling, "boost pays once"), so for each:
--           the start turn's attack is the beast's special; every damage it
--           deals leaves unmultiplied; if it runs through FightAttack (the
--           physical "Special", attack $EF, which GetCmdForAI maps to command
--           $00) Ot6FightBoost leaves the multi-attack count where FightAttack
--           put it; and the pips are charged exactly as for any boosted
--           action (bank - 3, pending cleared).  At least one cell's special
--           ran under a command other than Fight and at least one ran through
--           FightAttack, so both classes stay covered.
--
-- Why $3a70 and not a count of hits.  FightAttack stores the vanilla count (1,
-- or 7 with an Offering) and calls Ot6FightBoost on the next instruction, and
-- the multi-attack loop runs $3a70 + 1 passes (`dec $3a70 / bmi`), so $3a70 at
-- Ot6FightBoost's entry is exactly the unboosted count and $3a70 at the
-- instruction after its call is exactly what the boost made of it; nothing
-- else writes it in between.  A count of damage calls is not exact: an empty
-- hand's pass whiffs, a miss or a death ends passes early, and the unboosted
-- baseline for the SAME special needs the 0-pip coin to land on it (1 in 2).
-- Negative controls: f0484b6f (OT6_ROM/OT6_DBG) fails `rod` (Ice 2 read as a
-- folded cast); a build with Ot6WeaponSpellQueued's store NOPed fails `fight`;
-- 95fc3f30 (no queued-Rage test) fails `rage` (a special multiplied);
-- 8032a150 (no Rage gate in Ot6FightBoost) fails `rage` at the first physical
-- Special ($3a70 1 -> 7: three pips bought six more swings on top of the
-- special they had already made certain).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local BOOST = 3
local MULT = 1 << BOOST
-- What Ot6BoostDmg makes of `din` at BOOST: BOOST doublings of the 16-bit
-- word, saturating at $FFFF when one of them carries out of bit 15 (`asl /
-- bcs @cap`, ot6_boostdmg.asm), like the rest of the engine's damage math.
-- Until #359 the cap was $7FFF, so a product past $FFFF fell below the
-- products under it; battle_boostcap reaches that arm.
local function boosted(din)
  local v = din * MULT
  if v > 0xFFFF then return 0xFFFF end      -- #359: saturates at $ffff
  return v
end
local TERRA, LOCKE, SHADOW = 0x00, 0x01, 0x03
local ICE_ROD, MITHRIL_KNIFE, MAGICITE = 0x36, 0x01, 0xF9
local FIRE, FIRE3 = 0x00, 0x09
-- Try n of a retried case gives the actor's first n-1 windows to the bench
-- (tryCase), so its reach is bounded by 6000 frames (the single-window
-- reach the suite always had; the longest try-1 reach measured is 1406,
-- rod in px13/new7/new_k10)
-- plus ROUND_FRAMES per window spent.  Measured per spent window, try n's
-- reach less try 1's over n-1: 550, 653, 1051, 3157 and 3345 frames
-- (build/attempts/wt/procboost-v024/reach_frames.txt, the final sweep and
-- its replay); ROUND_FRAMES is twice the largest.
local FIGHT_TRIES, ROUND_FRAMES = 12, 2 * 3345
local GAU, RAGE_ENTRIES = 0x0B, 8          -- the rage window lists at most eight
local GAU_ENCOUNTERS = 4                   -- Veldt encounters taken for GAU's window (#411)
local GAU_STATE = "build/states/gau_joined.mss.lua"
local RAGECOUNT, RAGEBEAST, MP = 0x3A9A, 0x33A8, 0x3C08

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local ST_ITEM, ST_MAGIC, ST_THROW, ST_RAGE = 0x0A, 0x0E, 0x2D, 0x1E
local RSCROLL, RCOL, RROW = 0x892B, 0x892F, 0x8933   -- the rage cursor, by slot
local ITEMLIST, BATTINV = 0x4005, 0x2686
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local THROW_SCROLL, THROW_ROW = 0x8953, 0x895B
local MSCROLL, MCOL, MROW, MLISTPTR = 0x8913, 0x8917, 0x891B, 0x302C
local BANK, PEND = 0x3E9C, 0x3E9D
local HANDS = 0x3CA8
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_THROW, CMD_RAGE = 0x00, 0x01, 0x02, 0x08, 0x10
local CMD_SUMMON = 0x19                       -- what GetCmdForAI names an esper's attack

local slotOf, snap, armed = {}, nil, nil
local snapSeats                               -- the seats as the snapshot was taken
local SETTLE, settled = 8, 0                  -- released frames on its window first
local unreadySaid = -1200
local weapspell                               -- OT6_WEAPSPELL, off the dbg
local learned                                 -- GAU's rage-window length

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
    -- command $29 is no action anyone queued: the engine runs it for an
    -- entity whose Stop, Reflect, Freeze or Psyche counter just ran out
    -- (battle_main.asm Cmd_29), and it reaches Ot6BoostDmg with 0 in.  One
    -- landed on GAU between his Rage's confirm and its end on a varied
    -- Veldt draw and failed "the queued command is Rage: got 41 ($29)"
    -- (build/attempts/wt/procboost-v024/px13/rage8/old_k2.log.gz).
    if H.readByte(0x3A7C) == 0x29 then
      armed.timers = (armed.timers or 0) + 1
      return
    end
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
  -- Ot6FightBoost: $3a70 at its entry (FightAttack's vanilla count) and at
  -- the instruction after its one call site (what the boost made of it)
  local fb = H.sym("Ot6FightBoost")
  local f0, f1, f2 = fb & 0xFF, (fb >> 8) & 0xFF, (fb >> 16) & 0xFF
  local fsites = {}
  for off = 0x020000, 0x02FFFC do
    if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == f0
       and H.readRomByte(off + 2) == f1 and H.readRomByte(off + 3) == f2 then
      fsites[#fsites + 1] = 0xC00000 + off + 4
    end
  end
  H.assertEq(#fsites, 1, "Ot6FightBoost has one call site in bank $C2 (FightAttack)")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x ~= armed.slot * 2 then return end
    armed.fb[#armed.fb + 1] = {
      a7c = H.readByte(0x3A7C), a7d = H.readByte(0x3A7D), pend = H.readByte(PEND + x),
      before = H.readByte(0x3A70) }
  end, emu.callbackType.exec, fb, fb)
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF or #armed.fb == 0 then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) ~= armed.slot * 2 then return end
    local f = armed.fb[#armed.fb]
    if f.after == nil then f.after = H.readByte(0x3A70) end
  end, emu.callbackType.exec, fsites[1], fsites[1])
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x == armed.slot * 2 then
      armed.endF = H.frame
      armed.beast = H.readByte(RAGEBEAST + x)
    end
  end, emu.callbackType.exec, ae, ae)
  -- the Magicite's draw: AttackerEffect_49 is `jsr RandGenju`, then (#368)
  -- `jsl Ot6MagiciteKeep / bcs` back to its top for a boosted draw the boost
  -- cannot pay for, then `sta $3400`; so A at the instruction after the jsr
  -- is each draw, and the last one is the esper.  Tempest's effect
  -- branches into that same sta (wind slash), so only a pass that entered
  -- AttackerEffect_49 counts.
  local e49 = H.sym("AttackerEffect_49")
  local rg = H.sym("RandGenju")
  H.assertEq(H.readRomByte((e49 & 0x3FFFFF)) == 0x20 and H.readRomWord((e49 & 0x3FFFFF) + 1) == (rg & 0xFFFF),
    true, "AttackerEffect_49 opens with jsr RandGenju")
  local drawing = false
  emu.addMemoryCallback(function()
    drawing = armed ~= nil and not armed.endF
  end, emu.callbackType.exec, e49, e49)
  emu.addMemoryCallback(function()
    if not drawing then return end
    drawing = false
    if armed == nil or armed.endF then return end
    armed.esper = emu.getState()["cpu.a"] & 0xFF
    armed.drawn = armed.drawn or {}
    armed.drawn[#armed.drawn + 1] = armed.esper   -- every draw, kept or not
  end, emu.callbackType.exec, e49 + 3, e49 + 3)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end

-- The bench: everyone but `except` keeps the party standing, so the action
-- under measurement lives to resolve.  A window with someone down gives a
-- Fenix Down; one with a status a bag item lifts gives that item; one with
-- a member under HEAL_PCT of max HP gives the most hurt of them a Potion
-- (an X-Potion under a quarter, a Tonic when the Potions are gone); any
-- other window takes a real Defend (RIGHT opens Def., A commits it).
-- Healing, like a Defend, is an unboosted action, so it banks the actor's
-- pip.  Healing comes first because the encounter is whatever 394 deals:
-- on the v0.24 re-cut a lone Ninja (formation 0003) took half of every bar
-- while the banks filled (1207 -> 600 on TERRA), and with the others
-- Defending through its party-wide hits the party wiped inside the rod
-- case: LOCKE's Ice Rod committed (f5754) and never went off before the
-- wipe (canary f6788; build/attempts/wt/v024-recut/qual1/procboost_hpdiag.log).
-- battle_boostcharge's bench, which this follows, heals first for the same
-- reason.  HEAL_PCT sits above READY_PCT, the snapshot's floor: healing
-- only members under the floor itself, a Potion (about 250) at a time
-- against chip damage on four bars, held the party within a few points of
-- it for 30000 frames and never had all four over it at once
-- (build/attempts/wt/procboost-v024/air/new4/new_k5.log.gz).
local TONIC, POTION, XPOTION, FENIX = 0xE8, 0xE9, 0xEA, 0xF0
local HEAL_PCT, READY_PCT = 75, 60
local HP, MAXHP = 0x3BF4, 0x3C1C
local tc = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })
local benchTick, plans, benchHeals = 0, {}, 0
local function seated(s) return H.readByte(BCHID + s * 2) ~= 0xFF end
local function seatsLine()
  local t = {}
  for s = 0, 3 do
    if seated(s) then
      t[#t + 1] = string.format("a%d:%d/%d", s, H.readWord(HP + s * 2), H.readWord(MAXHP + s * 2))
    end
  end
  return table.concat(t, " ")
end
-- every seated member alive and at or above READY_PCT of max HP
local function standing()
  for s = 0, 3 do
    if seated(s) then
      local hp, mx = H.readWord(HP + s * 2), H.readWord(MAXHP + s * 2)
      if hp == 0 or hp * 100 < READY_PCT * mx then return false end
    end
  end
  return true
end
local function statusBytes(s)
  return H.readByte(0x3EE4 + s * 2), H.readByte(0x3EE5 + s * 2),
         H.readByte(0x3EF8 + s * 2), H.readByte(0x3EF9 + s * 2)
end
-- The statuses a bag item lifts that keep a member from acting as told:
-- Petrify (Soft), Imp and Mute (each greys commands; Green Cherry, Echo
-- Screen), Zombie (Holy Water), with Remedy behind each.  Which item
-- clears which bit is read from the ROM's own records (H.statusCure).
-- Sleep and Muddle lift under any physical hit and Stop on its counter;
-- nothing here hits an ally, so those are waited out (a case's actor
-- under one defers, below).
local ST2_MUTE = 0x08
local STATUS_CURES = {
  { byte = 1, bit = H.ST1_PETRIFY, name = "Petrify", items = { H.SOFT, H.REMEDY } },
  { byte = 1, bit = H.ST1_ZOMBIE, name = "Zombie", items = { H.REVIVIFY, H.REMEDY } },
  { byte = 1, bit = H.ST1_IMP, name = "Imp", items = { H.GREEN_CHERRY, H.REMEDY }, greys = true },
  { byte = 2, bit = ST2_MUTE, name = "Mute", items = { 0xFB, H.REMEDY }, greys = true },
}
-- A member someone has already queued care for is left to it until it
-- lands (the HP rises, or the status the item was for clears) or
-- INBOUND_WAIT frames pass: three windows in a row once queued three
-- Potions on one member at 58% before the first went off
-- (build/attempts/wt/procboost-v024/px13/new3/new_k6.log.gz, f32864-f33304).
local INBOUND_WAIT = 600
local inbound = {}
local function awaiting(s)
  local r = inbound[s]
  if r == nil then return false end
  local s1, s2 = statusBytes(s)
  local landed = H.readWord(HP + s * 2) > r.hp
    or (r.bit ~= nil and (((r.byte == 1) and s1 or s2) & r.bit) == 0)
  if landed or H.frame - r.f > INBOUND_WAIT then inbound[s] = nil return false end
  return true
end
local activeCases, blocked     -- the cases this half measures, and blocked(c) (below)
local function cureFor(s, greys)
  local s1, s2 = statusBytes(s)
  for _, k in ipairs(STATUS_CURES) do
    if (k.greys == true) == greys and ((k.byte == 1 and s1 or s2) & k.bit) ~= 0 then
      local item = H.statusCure({ byte = k.byte, bit = k.bit, items = k.items,
                                  has = function(id) return battInvIdx(id) ~= nil end })
      if item then return { item = item, target = s, why = k.name, byte = k.byte, bit = k.bit } end
    end
  end
end
local function carePlan()
  for s = 0, 3 do
    if seated(s) and H.readWord(HP + s * 2) == 0 and battInvIdx(FENIX) and not awaiting(s) then
      return { item = FENIX, target = s, why = "down" }
    end
  end
  -- Petrify or Zombie takes a member out of the bench: lift it on anyone
  for s = 0, 3 do
    if seated(s) and H.readWord(HP + s * 2) > 0 and not awaiting(s) then
      local plan = cureFor(s, false)
      if plan then return plan end
    end
  end
  -- Imp and Mute only grey commands, and the bag holds few of their cures
  -- (one Echo Screen and no Remedy at fc_alcove): lift one only on a
  -- case's actor whose verb row it greys, the cases in order, so the
  -- caster first.  Curing SHADOW's Mute, which greys nothing he throws,
  -- spent the only Echo Screen and left TERRA's Mute nothing
  -- (build/attempts/wt/procboost-v024/px13/new7/new_k5.log.gz, f19826).
  for _, c in ipairs(activeCases or {}) do
    local s = slotOf[c.char]
    if s ~= nil and seated(s) and H.readWord(HP + s * 2) > 0 and not awaiting(s) then
      local why = blocked(c)
      if why and why:find("greyed", 1, true) then
        local plan = cureFor(s, true)
        if plan then return plan end
      end
    end
  end
  local worst, wpct = nil, nil
  for s = 0, 3 do
    local hp, mx = H.readWord(HP + s * 2), H.readWord(MAXHP + s * 2)
    if seated(s) and hp > 0 and mx > 0 and not awaiting(s) then
      local pct = hp * 100 // mx
      if wpct == nil or pct < wpct then worst, wpct = s, pct end
    end
  end
  if worst == nil or wpct >= HEAL_PCT then return nil end
  local item = (wpct < 25 and battInvIdx(XPOTION) and XPOTION)
            or (battInvIdx(POTION) and POTION) or (battInvIdx(TONIC) and TONIC) or nil
  if item == nil then return nil end
  return { item = item, target = worst, why = string.format("at %d%%", wpct) }
end
local function bench(except)
  benchTick = benchTick + 1
  tc.observe()
  if H.readByte(MENU) == 0 then H.setPad({}) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then H.setPad({}) return end
  local btn
  if st == ST_CMD then
    local p = carePlan()
    plans[a] = p
    local row = p and cmdRow(a, CMD_ITEM)
    if row == nil then
      btn = "right"
    else
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == row) and "a" or ((cur < row) and "down" or "up")
    end
  elseif st == ST_DEF then
    btn = "a"
  elseif st == ST_ITEM then
    local p = plans[a]
    local want = p and battInvIdx(p.item)
    if want == nil then
      btn = "b"
    else
      local cur = H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
      btn = (cur < want and "down") or (cur > want and "up") or "a"
    end
  elseif st == ST_TGT then
    local p = plans[a]
    if p == nil then
      btn = "b"
    else
      btn = tc.steer(p.target, benchTick)
      if btn == "a" and not p.said then
        p.said = true
        benchHeals = benchHeals + 1
        inbound[p.target] = { f = H.frame, hp = H.readWord(HP + p.target * 2),
                              byte = p.byte, bit = p.bit }
        H.log(string.format("[procboost] bench f%d: slot %d gives item $%02X to slot %d (%s); seats %s",
          H.frame, a, p.item, p.target, p.why, seatsLine()))
      end
      H.setPad((btn and (benchTick - 1) % 16 < 4) and { [btn] = true } or {})
      return
    end
  end
  H.setPad((btn and benchTick % 12 < 6) and { [btn] = true } or {})
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
  elseif c.verb == "rage" then
    if st ~= ST_RAGE then return nil end
    local wr, wc = c.entry // 2, c.entry % 2
    local row = H.readByte(RSCROLL + s) + H.readByte(RROW + s)
    local col = H.readByte(RCOL + s)
    if col ~= wc then return wc > col and "right" or "left" end
    if row ~= wr then return wr > row and "down" or "up" end
    return "a"
  end
end

local CMD_OF = { fight = CMD_FIGHT, throw = CMD_THROW, item = CMD_ITEM, magic = CMD_MAGIC,
                 rage = CMD_RAGE }
local LIST_OF = { throw = ST_THROW, item = ST_ITEM, magic = ST_MAGIC, rage = ST_RAGE }
local phase, held = "idle", nil
-- Why a case's actor cannot play its verb now, or nil: down, a status that
-- takes the turn or the choice of command away (H.turnDenied, Muddle,
-- Zombie), or the verb's command row greyed -- Mute or Imp greys Magic,
-- and btlgfx skips a row whose flags bit 7 is set, so no press lands on it
-- (#153).  On the re-cut, a $0B7 draw (Brainpans, Misfit, Apokryphos)
-- muted TERRA before the snapshot and the magic case walked the cursor
-- up and down past the greyed row for 6000 frames
-- (build/attempts/wt/procboost-v024/air/old2/old_k6.log.gz).
function blocked(c)
  local s = slotOf[c.char]
  if s == nil or not seated(s) then return "not seated" end
  if H.readWord(HP + s * 2) == 0 then return "down" end
  local s1, s2, s3, s4 = statusBytes(s)
  local den = H.turnDenied({ s1 = s1, s2 = s2, s3 = s3, s4 = s4 })
  if den then return den end
  if (s2 & H.ST2_MUDDLE) ~= 0 then return "Muddle" end
  if (s1 & H.ST1_ZOMBIE) ~= 0 then return "Zombie" end
  local row = cmdRow(s, CMD_OF[c.verb])
  if row == nil then return "no " .. c.verb .. " command" end
  if (H.readByte(CMDTBL + s * 12 + row * 3 + 1) & 0x80) ~= 0 then
    return string.format("the %s row greyed (status bytes %02X %02X)", c.verb, s1, s2)
  end
  return nil
end
-- the pending boost, bank and MP as the action is committed; arms the observers
local function markConfirm(c)
  local e = c.slot * 2
  c.pendAtConfirm, c.bankAtConfirm = H.readByte(PEND + e), H.readByte(BANK + e)
  c.mpAtConfirm, armed = H.readWord(MP + e), c
end
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
      markConfirm(c)
      phase = "target"
    end
    return b
  end
  if phase == "target" then
    if H.readByte(MENU) == 0 or a ~= c.slot then phase = "sent" return nil end
    if st == ST_CMD or st == LIST_OF[c.verb] then return "a" end   -- not taken
    if st ~= ST_TGT then return nil end
    markConfirm(c)
    phase = "confirmed"
    return "a"
  end
end

local function describe(k)
  return string.format("b5=$%02X b6=$%02X 3a7c=$%02X 3a7d=$%02X p%d ws=$%02X %d->%s",
    k.b5, k.b6, k.a7c, k.a7d, k.pend, k.ws, k.din, tostring(k.dout))
end
local function describeFb(f)
  return string.format("3a7c=$%02X 3a7d=$%02X p%d 3a70 %d->%s",
    f.a7c, f.a7d, f.pend, f.before, tostring(f.after))
end
local function specialOf(beast)
  return H.readRomByte((H.sym("MonsterRage") & 0x3FFFFF) + beast * 2 + 1)
end

-- one try of a case from the snapshot; `c.done(c)` says whether the try
-- produced the thing the case is about (nil = any try does)
local function tryCase(c, n)
  local req, spent, skip, deferring = nil, 0, false, nil
  return {
    H.call(function()
      skip = c.hit ~= nil or (c.present ~= nil and not c.present())
      if skip then return end
      H.setPad({})
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      if skip then return end
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      inbound = {}
      c.slot = slotOf[c.char]
      c.calls, c.fb, c.endF, c.beast, c.timers = {}, {}, nil, nil, nil
      c.esper, c.cutF, c.cutSeats, c.drawn = nil, nil, nil, nil
      c.pendAtConfirm, c.bankAtConfirm, c.mpAtConfirm = nil, nil, nil
      c.spend = n - 1
      tick, phase, held, spent, deferring = 0, "reach", nil, 0, nil
    end),
    H.driveUntil(function() return skip or phase == "sent" end, 6000 + (n - 1) * ROUND_FRAMES, {
      H.call(function()
        if phase == "reach" then
          -- bench the other windows until this actor's opens.  Try n gives
          -- the actor's first n-1 windows to the bench, so each try acts
          -- after n-1 more rounds of everyone's turns.  The idle waits this
          -- replaced (48 frames more a try) did not vary the swings: on one
          -- draw $be stood at $C5 through every wait of tries 1-4 and moved
          -- only once a monster acted inside the wait ($C7 and $CE from
          -- wait 145, $D5 in try 9, $DE in try 12), and all twelve tries
          -- swung the same four hits
          -- (build/attempts/wt/procboost-v024/px13/diagbe/diagbe_k4.log.gz).
          -- An actor who cannot play the verb at a window (blocked)
          -- spends it the same way, and the case starts at one where they
          -- can.
          local mine = H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == c.slot
          if not mine then
            deferring = nil
            bench(c.slot)
          elseif deferring then
            bench(-1)
          elseif H.readByte(MSTATE) ~= ST_CMD then
            -- a sub-window of the actor's own: back out to its command list
            local st = H.readByte(MSTATE)
            pulse((st == ST_DEF or st == ST_TGT or st == ST_ITEM or st == ST_MAGIC
                   or st == ST_THROW or st == ST_RAGE) and "b" or nil)
          else
            local why = blocked(c)
            if why then
              H.log(string.format("[procboost] %s try %d: slot %d's window at f%d, but %s: "
                .. "the bench plays it; seats %s", c.name, n, c.slot, H.frame, why, seatsLine()))
            elseif spent < c.spend then
              spent = spent + 1
              why = "spent"
            end
            if why then
              deferring = why
              bench(-1)
            else
              H.setPad({})
              phase, tick = "boost", 0
            end
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
    H.driveUntil(function()
      return skip or c.cutF ~= nil or (c.endF ~= nil and H.frame >= c.endF + 30)
    end, 6000, {
      H.call(function()
        if c.cut and c.cut(c) then
          c.cutF, c.cutSeats = H.frame, seatsLine()
          H.setPad({})
          return
        end
        bench(c.slot)
      end),
    }, c.name .. " resolves, try " .. n),
    H.call(function()
      if skip then return end
      armed = nil
      H.setPad({})
      if c.cutF then
        -- the action wiped the party (the case's cut says why): the branch
        -- ends here, and the snapshot comes back so no frame of the wipe
        -- plays on into the next step
        req = H.requestLoadState(snap.blob)
      end
      local e = c.slot * 2
      local bankAfter, pendAfter = H.readByte(BANK + e), H.readByte(PEND + e)
      local mpAfter = H.readWord(MP + e)
      local parts, fparts = {}, {}
      for _, k in ipairs(c.calls) do parts[#parts + 1] = describe(k) end
      for _, f in ipairs(c.fb) do fparts[#fparts + 1] = describeFb(f) end
      local who = ""
      if c.verb == "rage" and c.beast then
        who = string.format("beast $%02X (special $%02X), ", c.beast, specialOf(c.beast))
      end
      H.log(string.format("[procboost] %s try %d (%d window(s) spent first): %spending at confirm %s: %s"
        .. " ; Ot6FightBoost: %s ; bank %s->%d pending %d, mp %s->%d%s",
        c.name, n, c.spend, who, tostring(c.pendAtConfirm),
        #parts > 0 and table.concat(parts, " | ") or "no Ot6BoostDmg call",
        #fparts > 0 and table.concat(fparts, " | ") or "not reached",
        tostring(c.bankAtConfirm), bankAfter, pendAfter, tostring(c.mpAtConfirm), mpAfter,
        c.timers and string.format(" ; %d status-timer call(s) ($29) left out", c.timers) or ""))
      local measured = c.done == nil or c.done(c)
      if c.note then
        local note = c.note(c, measured)
        c.draws = c.draws or {}
        c.draws[#c.draws + 1] = string.format("try %d: %s", n, note)
        H.log(string.format("[procboost] %s try %d: %s", c.name, n, note))
      end
      if measured then
        c.hit = { calls = c.calls, fb = c.fb, n = n, pendAtConfirm = c.pendAtConfirm,
                  bankAtConfirm = c.bankAtConfirm, bankAfter = bankAfter, pendAfter = pendAfter,
                  beast = c.beast, esper = c.esper, cutF = c.cutF }
      end
      if c.drawn then
        c.drawsByTry = c.drawsByTry or {}
        c.drawsByTry[#c.drawsByTry + 1] = c.drawn
      end
    end),
    H.waitFrames(2),
    H.call(function()
      if not skip and c.cutF then H.checkReq(req, "snapshot load after the wipe") end
    end),
  }
end

-- The Magicite item's esper pool, from the ROM.  AttackerEffect_49 draws
-- it with RandGenju (battle_main.asm):
--   lda #n / jsr RandA / cmp #skip / bcc + / inc / inc / + clc / adc #base
-- so r = RandA(n) picks esper base + r, or base + r + 2 from r = skip on
-- (vanilla's n=$19, skip=$0B, base=$36: never Odin or Raiden).  RandA is
-- RNGTbl[++$be] * n / 256, and RNGTbl is a permutation of 0..255, so each
-- esper's odds are its share of the 256 table entries.  Each esper's
-- MagicProp record (+$00 targeting; +$02 flags: bit 7 "can't target
-- characters", bit 2 "can hit dead targets"; +$04 bit 0 heal; +$06 power)
-- says what its draw gives the case.  The side an auto-targeted attack
-- lands on is the targeting byte's (the side chooser at C2/5937 in
-- ff6/notes/ff3u.asm): ($bb & $0C) == $04 is every body on both sides, and
-- otherwise bit 6 picks the enemy side over the caster's; flags bit 7 then
-- strikes the characters out (_MaskTarget, C2/58FA).  So the party is in
-- an esper's targets when its targeting is both-sides or own-side and
-- flags bit 7 is clear:
--   power 0 (Siren, Shoat, Stray, Palidor, Ragnarok and the party buffs):
--     no damage, so nothing for the boost to multiply; the case tries again
--   resurrection targeting (Phoenix): its heal may land on no living body;
--     counted with the power-0 draws for the try bound
--   damage that reaches the party, not a heal (Crusader's Purifier,
--     targeting $04 and flags $40, the same record as vanilla's): it hits
--     every body on the field.  At x8 the per-target damage is the 9999 cap, past any party's
--     max HP here, so no brace saves the party (on the care-policy chain's
--     fc_alcove, base 7243 left as 57944 and each seat took 9999,
--     build/attempts/wt/procboost-magicite/diag/diagm2_k0.log.gz).  The
--     call is measured and the branch ends at the wipe, before the run's
--     canary would read it as the run's game over: the snapshot is restored.
--   everything else: damage or healing that leaves x8.
local RNGTBL_N = 256
local function magicitePool()
  local rg = H.sym("RandGenju") & 0x3FFFFF
  local b = {}
  for i = 0, 13 do b[i] = H.readRomByte(rg + i) end
  local ra = H.sym("RandA")
  H.assertEq(b[0] == 0xA9 and b[2] == 0x20 and (b[3] | b[4] << 8) == (ra & 0xFFFF) and b[5] == 0xC9
    and b[7] == 0x90 and b[8] == 0x02 and b[9] == 0x1A and b[10] == 0x1A and b[11] == 0x18
    and b[12] == 0x69, true, "RandGenju is lda #n / jsr RandA / cmp #skip / bcc / inc / inc / clc / adc #base")
  local n, skip, base = b[1], b[6], b[13]
  local rng = H.sym("RNGTbl") & 0x3FFFFF
  local share = {}
  for i = 0, RNGTBL_N - 1 do
    local r = (H.readRomByte(rng + i) * n) >> 8
    share[r] = (share[r] or 0) + 1
  end
  local mp, names = H.sym("MagicProp") & 0x3FFFFF, H.sym("GenjuName") & 0x3FFFFF
  local pool, pays = {}, 0
  for r = 0, n - 1 do
    local id = base + r + (r >= skip and 2 or 0)
    local rec = mp + id * 14
    local tgt, flags = H.readRomByte(rec), H.readRomByte(rec + 2)
    local heal, power = (H.readRomByte(rec + 4) & 0x01) ~= 0, H.readRomByte(rec + 6)
    local side = ((tgt & 0x0C) == 0x04 and "both") or ((tgt & 0x40) ~= 0 and "enemy") or "party"
    local reachesParty = side ~= "enemy" and (flags & 0x80) == 0
    local name = {}
    for j = 0, 7 do
      local ch = H.readRomByte(names + (id - base) * 8 + j)
      if ch >= 0x80 and ch <= 0x99 then name[#name + 1] = string.char(65 + ch - 0x80)
      elseif ch >= 0x9A and ch <= 0xB3 then name[#name + 1] = string.char(97 + ch - 0x9A) end
    end
    local e = { id = id, name = table.concat(name), power = power, heal = heal, odds = (share[r] or 0),
                side = side, hitsParty = power > 0 and not heal and reachesParty,
                idle = power == 0 or (flags & 0x04) ~= 0 }
    -- what a boosted draw keeps (#368, Ot6MagiciteKeep): something to
    -- multiply, on the enemy or as a heal, never onto the party
    e.pays = not e.idle and not e.hitsParty
    if e.pays then pays = pays + e.odds end
    pool[id] = e
  end
  local q = pays / RNGTBL_N
  assert(q > 0 and q < 1, "the Magicite's pool holds espers a boost pays for, and others")
  return pool, q, n
end
-- Decoded as the script loads, because the try count shapes the steps; an
-- error raised here, before H.run, hangs the testrunner silently until
-- OT6_TIMEOUT (a mutant of the RandGenju check sat 30 minutes with no line
-- logged), so it is caught and raised again from the run's first step.
local poolOk, MAGICITE_POOL, MAGICITE_PAYS, MAGICITE_N = pcall(magicitePool)
local poolErr = nil
if not poolOk then
  poolErr, MAGICITE_POOL, MAGICITE_PAYS, MAGICITE_N = tostring(MAGICITE_POOL), {}, 0.5, 0
end
-- tries until one redraws: the least N with q^N <= MAGICITE_FAIL, q the
-- share of first draws that already pay (a try that redraws nothing shows
-- the keep arm only; each try draws a round later than the last, at another
-- point of the RNG)
local MAGICITE_FAIL = 1e-3
local MAGICITE_TRIES = math.max(1, math.ceil(math.log(MAGICITE_FAIL) / math.log(MAGICITE_PAYS)))
local function esperName(id)
  local e = id and MAGICITE_POOL[id]
  return id == nil and "no draw seen" or string.format("$%02X %s", id, e and e.name or "(not in the pool)")
end
-- the call that measures a Magicite try: the drawn esper's attack, run as a
-- summon, at the pending boost, with damage (or healing) to multiply
local function magiciteCall(c, calls)
  for _, k in ipairs(calls or c.calls) do
    if k.pend == BOOST and k.din > 0 and k.b5 == CMD_SUMMON and k.b6 == c.esper then return k end
  end
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
    -- measured, and some try so far drew again (the redraw arm ran)
    done = function(c)
      if c.drawn and #c.drawn > 1 then c.sawRedraw = true end
      return magiciteCall(c) ~= nil and c.sawRedraw == true
    end,
    -- the drawn esper hits the party and the party is down: the branch ends
    cut = function(c)
      local e = c.esper and MAGICITE_POOL[c.esper]
      return e ~= nil and e.hitsParty and magiciteCall(c) ~= nil and H.partyWipedInBattle()
    end,
    note = function(c, measured)
      local e = c.esper and MAGICITE_POOL[c.esper]
      local k = magiciteCall(c)
      local what
      if c.esper == nil then
        what = "no esper drawn"
      elseif k then
        what = string.format("%d -> %d%s", k.din, k.dout,
          measured and "" or " (no try has drawn again yet)")
      elseif e and e.power == 0 then
        what = "power 0, nothing to multiply"
      else
        what = "no damage or healing at the pending boost"
      end
      local before = {}
      for i = 1, #(c.drawn or {}) - 1 do before[#before + 1] = esperName(c.drawn[i]) end
      return string.format("the Magicite drew %s%s: %s%s",
        #before > 0 and (table.concat(before, ", ") .. ", drew again, then ") or "",
        esperName(c.esper), what,
        c.cutF and string.format("; it hit the party too, wiped at f%d (seats %s): the branch ends, "
          .. "the snapshot restored", c.cutF, c.cutSeats) or "")
    end },
}
activeCases = CASES
-- The precondition every case starts from: every member alive at READY_PCT
-- of max HP or better, and every case's actor free to play its verb.
local function ready()
  if not standing() then
    return false, string.format("a member down or under %d%% of max HP", READY_PCT)
  end
  for _, c in ipairs(activeCases) do
    local why = blocked(c)
    if why then return false, c.name .. ": " .. why end
  end
  return true, nil
end

-- Why a case's actor stays blocked for the rest of this battle, or nil:
-- down with no Fenix Down in the bag, or under a status that lasts the
-- battle (Petrify, Zombie, Imp, Mute) and that nothing in the bag lifts.
local function unliftable()
  for _, c in ipairs(activeCases) do
    local s = slotOf[c.char]
    local why = s ~= nil and not awaiting(s) and blocked(c) or nil
    if why == "down" and battInvIdx(FENIX) == nil then
      return c.name .. ": down, and no Fenix Down in the bag"
    end
    if why ~= nil and why ~= "down" then
      -- the status behind this block: Petrify or Zombie by name, Imp or
      -- Mute for a greyed row (a Sleep, a Stop or a Muddle wears off)
      local greyed = why:find("greyed", 1, true) ~= nil
      local s1, s2 = statusBytes(s)
      for _, k in ipairs(STATUS_CURES) do
        if ((k.byte == 1 and s1 or s2) & k.bit) ~= 0 and (why == k.name or (greyed and k.greys))
           and H.statusCure({ byte = k.byte, bit = k.bit, items = k.items,
                              has = function(id) return battInvIdx(id) ~= nil end }) == nil then
          return string.format("%s: %s, and nothing in the bag lifts it", c.name, k.name)
        end
      end
    end
  end
  return nil
end

-- Pace a lane off the arrival tile on 394 until an encounter comes.
local lane
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local paceTick, paceLost = 0, 0
local function paceFrame()
  paceTick = paceTick + 1
  if H.dialogWaiting() then                 -- a box the fight-out left: page it
    paceLost = 0
    H.setPad(paceTick % 8 < 4 and { a = true } or {})
    return
  end
  if not (H.hasControl() and H.tileAligned()) then
    paceLost = paceLost + 1
    if paceLost > 1800 then
      error(string.format("pacing 394: no control and no dialog for 1800 frames (f%d, map %d)",
        H.frame, H.mapId() & 0x3FF), 0)
    end
    H.setPad({})
    return
  end
  paceLost = 0
  local x, y = H.fieldX(), H.fieldY()
  if lane == nil then
    for _, d in ipairs({ "left", "right", "up", "down" }) do
      if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
    end
    if lane == nil then H.setPad({}) return end
  end
  H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
end

-- Read the battle that is up: the seats, TERRA's weapon spell, the draw.
-- How many battles to try before the precondition is called unreachable.
-- A battle fails to serve when a case's actor is blocked by something the
-- bag cannot lift (UNREADY_FRAMES is the backstop; no measured battle has
-- needed it).  Every block of that kind measured on 394 was a Mute, and
-- every Mute came in a formation holding an Apokryphos or a Misfit
-- (build/attempts/wt/procboost-v024/summary.txt).  394's pool is four
-- "+rand" words: the encounter counter picks the word, which the tables fix
-- for a given counter, and the word's base + rand(0..3) picks the
-- formation.  So whatever the counter, an encounter is such a formation
-- with odds at most q, the largest share of them in any word, and N
-- unservable battles in a row have odds at most q^N even if every such
-- formation always blocked.  MEASURE_BATTLES is the least N with
-- q^N <= MEASURE_FAIL.
local MUTERS = { [0x00C] = "Apokryphos", [0x0A4] = "Misfit" }
local MEASURE_FAIL = 1e-3
local function measureBattles()
  local pool = H.encounterPool(H.fieldEncounterGroup(394))
  local q = 0
  for slot = 1, 4 do
    local hit = 0
    for _, f in ipairs(pool[slot].formations) do
      for _, sp in ipairs(f.species) do
        if MUTERS[sp] then hit = hit + 1 break end
      end
    end
    q = math.max(q, hit / #pool[slot].formations)
  end
  assert(q < 1, "394's pool has a word that deals only Apokryphos/Misfit formations")
  return math.max(1, math.ceil(math.log(MEASURE_FAIL) / math.log(q))), q
end
local MEASURE_BATTLES, MUTER_ODDS = measureBattles()
local UNREADY_FRAMES = 20000
local serving = { n = 1, mode = "fill", since = nil, W = nil }
local function battleSetup()
  slotOf = {}
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
  local w = {}
  for _, v in ipairs(H.formationWords()) do w[#w + 1] = string.format("%04X", v) end
  H.log(string.format("[procboost] battle %d for the measurement: group $%04X, formation %s; seats %s",
    serving.n, H.readWord(0x11E0), table.concat(w, " "), seatsLine()))
end

local steps = {
  H.call(function() if poolErr then error("the Magicite's pool: " .. poolErr, 0) end end),
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
  H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function() paceFrame() end),
  }, "a random encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function() battleSetup() end),
  -- the bench plays every window until every bank holds BOOST and the party
  -- is ready (above), then snapshot the next command window once the pad
  -- has been released for SETTLE frames on it: a snapshot taken as one of
  -- the bench's Defend presses landed held LOCKE's Def. window open in
  -- every restore, and the rod case sat on it for 6000 frames
  -- (build/attempts/wt/procboost-v024/air/new2/new_k3.log.gz).
  -- A battle the party cannot get ready in (a case's actor blocked by
  -- something unliftable, or UNREADY_FRAMES with every bank full) is fought
  -- out by the route's walker and the next encounter taken, up to
  -- MEASURE_BATTLES: a Misfit's Mute on TERRA after the bag's
  -- one Echo Screen had gone to SHADOW held the magic row grey for 26000
  -- frames (build/attempts/wt/procboost-v024/px13/new5/new_k5.log.gz), and
  -- Mute ends with the battle.
  H.driveUntil(function() return snap ~= nil end, 30000 * MEASURE_BATTLES, {
    H.call(function()
      if serving.mode == "out" then
        if serving.W.frame() then return end      -- the battle, its reload, its care
        serving.mode = "pace"
      end
      if serving.mode == "pace" then
        if H.battleLoadStarted() then serving.mode = "up" H.setPad({}) return end
        paceFrame()
        return
      end
      if serving.mode == "up" then
        if not H.battleActive() then H.setPad({}) return end
        battleSetup()
        serving.mode, serving.since = "fill", nil
        return
      end
      local full = true
      for _, ch in ipairs({ TERRA, LOCKE, SHADOW }) do
        if H.readByte(BANK + slotOf[ch] * 2) < BOOST then full = false end
      end
      if full and ready() and H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD then
        H.setPad({})
        settled = settled + 1
        if settled >= SETTLE then
          snapSeats = seatsLine()
          snap = H.requestSaveState()
        end
        return
      end
      settled = 0
      if full then
        serving.since = serving.since or H.frame
        local stuck = unliftable()
        if stuck or H.frame - serving.since >= UNREADY_FRAMES then
          local why = stuck or select(2, ready())
          if serving.n >= MEASURE_BATTLES then
            error(string.format("precondition: no battle of %d let the party get ready (every "
              .. "member alive at %d%% of max HP or better and every case's actor free to play "
              .. "its verb); the last, %d frames after every bank filled: %s; seats %s",
              MEASURE_BATTLES, READY_PCT, H.frame - serving.since, why, seatsLine()), 0)
          end
          H.log(string.format("[procboost] battle %d cannot serve: %d frames after every bank "
            .. "reached %d, %s; fighting it out and taking the next encounter; seats %s",
            serving.n, H.frame - serving.since, BOOST, why, seatsLine()))
          serving.n, serving.mode = serving.n + 1, "out"
          serving.W = H.newWalkFighter("procboost: a battle that cannot serve")
          serving.W.frame()
          return
        end
      end
      if full and H.frame - unreadySaid >= 1200 then
        local _, why = ready()
        if why then
          unreadySaid = H.frame
          H.log(string.format("[procboost] f%d: every bank at %d, not ready yet: %s; seats %s",
            H.frame, BOOST, why, seatsLine()))
        end
      end
      bench(-1)
    end),
  }, string.format("every bank at %d, every member alive at %d%% of max HP and every case's actor "
    .. "free to play its verb, within %d battles", BOOST, READY_PCT, MEASURE_BATTLES)),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snap, "snapshot")
    -- the gate above is the precondition's check: it snapshots only a
    -- ready party, and a precondition no battle reaches is its error
    local idle, party, sides = {}, {}, {}
    for id = 0, 255 do
      local e = MAGICITE_POOL[id]
      if e and e.idle then idle[#idle + 1] = e.name end
      if e and e.hitsParty then party[#party + 1] = e.name end
      if e and e.power > 0 then sides[#sides + 1] = string.format("%s %s%s", e.name, e.side, e.heal and " heal" or "") end
    end
    H.log(string.format("[procboost] the Magicite's pool: %d espers from RandGenju; %.3f of a draw "
      .. "pays a boost; nothing to multiply: %s; hits the party too: %s; %d tries without a "
      .. "redraw at most %.4f",
      MAGICITE_N, MAGICITE_PAYS, table.concat(idle, " "),
      #party > 0 and table.concat(party, " ") or "none", MAGICITE_TRIES, MAGICITE_PAYS ^ MAGICITE_TRIES))
    H.log("[procboost] the Magicite's espers with power, by side: " .. table.concat(sides, ", "))
    H.log(string.format("[procboost] snapshot f%d in battle %d: seats %s, after %d bench "
      .. "action(s); %d battle(s) allowed (an Apokryphos/Misfit formation at most %.2f of a "
      .. "draw, so %d unservable in a row at most %.4f)", H.frame, serving.n, snapSeats,
      benchHeals, MEASURE_BATTLES, MUTER_ODDS, MEASURE_BATTLES, MUTER_ODDS ^ MEASURE_BATTLES))
  end),
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
    H.assertEq(c.hit ~= nil, true, c.name .. ": the case happened"
      .. (c.draws and " (" .. table.concat(c.draws, "; ") .. ")" or ""))
    H.assertEq(c.hit.pendAtConfirm, BOOST, c.name .. ": pending boost at the confirm")
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

  -- fight: the boost bought swings, seen by the observer the Rage row reads
  local f = by.fight.hit.fb[1]
  H.assertEq(f ~= nil and f.after ~= nil, true, "fight: FightAttack reached Ot6FightBoost")
  H.assertEq(f.after - f.before, 2 * BOOST, string.format(
    "fight: the boosted Fight's swings ($3a70 %d -> %d at pending %d)", f.before, f.after, f.pend))

  -- throw: MithrilKnife's id is Ice's, and a Throw is not a cast
  k = one(by.throw, function(k) return k.b5 == CMD_THROW end, "the throw")
  H.assertEq(k.a7d, MITHRIL_KNIFE, "throw: the queued attack is the knife")
  H.assertEq(k.dout, boosted(k.din), string.format(
    "throw: MithrilKnife leaves x%d (%d in)", MULT, k.din))

  -- rod: the Ice Rod runs as a command-$02 Ice 2 that nothing folded
  k = one(by.rod, function(k) return k.b5 == CMD_MAGIC end, "the rod's spell")
  H.assertEq(k.a7c, CMD_ITEM, "rod: the queued command is Item")
  H.assertEq(k.dout, boosted(k.din), string.format(
    "rod: the Ice Rod's spell $%02X leaves x%d (%d in)", k.b6, MULT, k.din))

  -- magicite (#368): every boosted draw kept an esper the boost pays for,
  -- and drew again only past ones it does not
  local redraws = 0
  for t, d in ipairs(by.magicite.drawsByTry or {}) do
    for i, id in ipairs(d) do
      local e = MAGICITE_POOL[id]
      H.assertEq(e ~= nil, true, string.format("magicite try %d: draw %d (%s) is in the pool", t, i, esperName(id)))
      if i < #d then
        redraws = redraws + 1
        H.assertEq(e.pays, false, string.format(
          "magicite try %d: drew again past %s, which the boost cannot pay for", t, esperName(id)))
      else
        H.assertEq(e.pays, true, string.format(
          "magicite try %d: the boosted Magicite kept %s, an esper the boost pays for "
          .. "(power, not a revival, not onto the party)", t, esperName(id)))
      end
    end
  end
  H.assertEq(redraws > 0, true, "magicite: a boosted draw was drawn again (the redraw arm ran)")

  -- magicite: the drawn esper's damage (or healing) is multiplied
  local mh = by.magicite.hit
  H.assertEq(MAGICITE_POOL[mh.esper] ~= nil, true, string.format(
    "magicite: the drawn esper (%s) is in the pool decoded from RandGenju", esperName(mh.esper)))
  k = magiciteCall({ esper = mh.esper }, mh.calls)
  H.assertEq(k ~= nil, true, "magicite: the drawn esper's attack ran as a summon with damage at the pending boost")
  H.assertEq(k.a7c, CMD_ITEM, "magicite: the queued command is Item")
  H.assertEq(k.a7d, MAGICITE, "magicite: the queued item is the Magicite")
  local mc = 0
  for _, k in ipairs(mh.calls) do
    if k.pend == BOOST and k.b5 == CMD_SUMMON and k.b6 == mh.esper then
      mc = mc + 1
      H.assertEq(k.dout, boosted(k.din), string.format(
        "magicite: the esper's $%02X leaves x%d (%d in)", k.b6, MULT, k.din))
    end
  end
  H.log(string.format("[procboost] verdict: magic skipped, %d weapon cast(s) unmultiplied "
    .. "(try %d), throw x%d, rod x%d, magicite x%d on %d call(s) (try %d of %d: %s%s)", casts,
    by.fight.hit.n, MULT, MULT, MULT, mc, mh.n, MAGICITE_TRIES, esperName(mh.esper),
    mh.cutF and ", which wiped the party; its branch ended there" or ""))
end)

-- ---- the Rage row, from gau_joined ---------------------------------------
local RAGE = {}
for e = 0, RAGE_ENTRIES - 1 do
  RAGE[#RAGE + 1] = { name = "rage entry " .. e, char = GAU, verb = "rage", entry = e, tries = 1,
                      present = function() return e < learned end }
end
for _, s in ipairs({
  H.call(function() snap, armed, inbound = nil, nil, {} end),
  H.loadState(GAU_STATE),
  H.waitFrames(20),
}) do steps[#steps + 1] = s end
-- #411: GAU can end an encounter unready (Berserk -- no cure is sold, #403
-- -- or the pack dead first); the Veldt is walked again, up to GAU_ENCOUNTERS
-- times, until his window is snapshotted.  On the a4e9f966 line's
-- gau_joined the first encounter berserked him and ended, and the
-- single-encounter drive read a closed battle for 30000 frames.
local function gauEncounter(k)
  return H.cond(function() return snap == nil end, {
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 6000, "world control (encounter " .. k .. ")", 5),
  (function()
    local dirs = { "left", "right", "up", "down" }
    local di, lastPos, n = 1, nil, 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not H.worldHasControl() then H.setPad({}) return end
        n = n + 1
        local pos = H.worldX() * 256 + H.worldY()
        if n >= 24 then
          if pos == lastPos then di = di % 4 + 1
          else di = (di % 2 == 1) and di + 1 or di - 1 end
          lastPos, n = pos, 0
        end
        H.setPad({ [dirs[di]] = true })
      end),
    }, "a Veldt encounter (" .. k .. ")")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "Veldt battle up", 5),
  H.call(function()
    slotOf = {}
    for s = 0, 3 do
      local id = H.readByte(BCHID + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[GAU], "GAU is in the battle")
    assert(cmdRow(slotOf[GAU], CMD_RAGE), "GAU has a Rage row")
    learned = H.readByte(RAGECOUNT)
    H.assertEq(learned >= 1 and learned <= RAGE_ENTRIES, true, string.format(
      "GAU's rage window lists 1..%d rages (%d)", RAGE_ENTRIES, learned))
    H.log(string.format("[procboost] GAU slot %d; %d rages learned", slotOf[GAU], learned))
  end),
  -- the same gate as the first half's: GAU's own window, his bank at
  -- BOOST, the party ready (activeCases is the Rage row now), the pad left
  -- alone for SETTLE frames on it
  H.call(function() activeCases, settled, unreadySaid = RAGE, 0, -1200 end),
  H.driveUntil(function() return snap ~= nil or not H.battleLoadStarted() end, 30000, {
    H.call(function()
      local s = slotOf[GAU]
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == s
         and H.readByte(BANK + s * 2) >= BOOST and H.readByte(PEND + s * 2) == 0 and ready() then
        H.setPad({})
        settled = settled + 1
        if settled >= SETTLE then
          snapSeats = seatsLine()
          snap = H.requestSaveState()
        end
        return
      end
      settled = 0
      if H.readByte(BANK + s * 2) >= BOOST and H.frame - unreadySaid >= 1200 then
        local _, why = ready()
        if why then
          unreadySaid = H.frame
          H.log(string.format("[procboost] f%d: GAU's bank at %d, not ready yet: %s; seats %s",
            H.frame, BOOST, why, seatsLine()))
        end
      end
      bench(-1)
    end),
  }, string.format("GAU's window with %d pips, every member alive at %d%% of max HP and GAU "
    .. "free to Rage (encounter " .. k .. ")", BOOST, READY_PCT)),
  H.call(function()
    H.setPad({})
    if snap == nil then
      H.log(string.format("[procboost] encounter %d ended before GAU's window was ready -- "
        .. "the next encounter", k))
    end
  end),
  }, {})
end
for k = 1, GAU_ENCOUNTERS do steps[#steps + 1] = gauEncounter(k) end
for _, s in ipairs({
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snap, "snapshot at GAU's window")
    H.log(string.format("[procboost] snapshot at GAU's window f%d: seats %s, after %d bench "
      .. "action(s)", H.frame, snapSeats, benchHeals))
  end),
}) do steps[#steps + 1] = s end
for _, c in ipairs(RAGE) do
  for _, s in ipairs(tryCase(c, 1)) do steps[#steps + 1] = s end
end
steps[#steps + 1] = H.call(function()
  local specials, dealt, covered, fights = 0, 0, 0, 0
  for _, c in ipairs(RAGE) do
    if c.entry < learned then
      H.assertEq(c.hit ~= nil, true, c.name .. ": the case happened")
      covered = covered + 1
      local h = c.hit
      H.assertEq(h.pendAtConfirm, BOOST, c.name .. ": pending boost at the confirm")
      H.assertEq(h.beast ~= nil, true, c.name .. ": the action ended (Ot6ActionEnd)")
      local special = specialOf(h.beast)
      H.assertEq(#h.calls + #h.fb > 0, true, c.name .. ": the start turn's attack was observed")
      for _, k in ipairs(h.calls) do
        H.assertEq(k.a7c, CMD_RAGE, c.name .. ": the queued command is Rage")
        H.assertEq(k.a7d, special, string.format(
          "%s: tier %d bought beast $%02X's special $%02X", c.name, BOOST, h.beast, special))
        if k.din > 0 then dealt = dealt + 1 end
        if k.b5 ~= CMD_FIGHT and k.b5 ~= CMD_RAGE and k.din > 0 then specials = specials + 1 end
        H.assertEq(k.dout, k.din, string.format(
          "%s: the beast's $%02X (command $%02X) leaves unmultiplied (%d in)", c.name, k.b6, k.b5, k.din))
      end
      -- the special's certainty was the whole purchase: a special that runs
      -- through FightAttack takes no swings on top of it
      for _, f in ipairs(h.fb) do
        fights = fights + 1
        H.assertEq(f.a7c, CMD_RAGE, c.name .. ": FightAttack ran for the queued Rage ($3a7c)")
        H.assertEq(f.a7d, special, string.format(
          "%s: FightAttack ran beast $%02X's special $%02X", c.name, h.beast, special))
        H.assertEq(f.after, f.before, string.format(
          "%s: beast $%02X's special $%02X gets no extra swings ($3a70 %d -> %s at pending %d)",
          c.name, h.beast, special, f.before, tostring(f.after), f.pend))
      end
      -- ...and the pips are charged exactly as for any boosted action
      H.assertEq(h.pendAfter, 0, c.name .. ": the pending boost is cleared at the action's end")
      H.assertEq(h.bankAfter, h.bankAtConfirm - BOOST, string.format(
        "%s: the %d pips are charged (bank %d -> %d)", c.name, BOOST, h.bankAtConfirm, h.bankAfter))
    end
  end
  H.assertEq(covered, learned, "every learned rage was played")
  H.assertEq(specials > 0, true, "a boosted Rage's special ran under its own command and dealt damage")
  H.assertEq(fights > 0, true, "a boosted Rage's special ran through FightAttack (a physical Special)")
  H.log(string.format("[procboost] rage verdict: %d of %d rages played; %d damage call(s) "
    .. "unmultiplied, %d of them a special under its own command; %d FightAttack special(s) "
    .. "with no extra swings; every start charged %d pips", covered, learned, dealt, specials,
    fights, BOOST))
end)

-- The run's cap is the sum of its steps' own bounds, so no step's budget is
-- cut short by it: the walk out, MEASURE_BATTLES battles at 30000, every
-- try's reach and resolve, and the Rage half's walk, gate and cases.
local function runBudget()
  local f = 20 + 20 + 3000 + 1800 + 900 + 30000 + 900 + 30000 * MEASURE_BATTLES
  for _, c in ipairs(CASES) do
    for n = 1, c.tries do f = f + 2 + 6000 + (n - 1) * ROUND_FRAMES + 6000 end
  end
  f = f + 20 + GAU_ENCOUNTERS * (6000 + 30000 + 900 + 30000) + 2
  for _ = 1, #RAGE do f = f + 2 + 6000 + 6000 end
  return f
end
H.run({ maxFrames = runBudget() }, steps)
