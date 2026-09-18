-- @suite slow savestate=camp_escaped
-- battle_mpcost.lua -- every ability costs MP: the OT6_MP_COSTS A/B.
--
-- One self-detecting instrument, run on both builds.  The shipped ROM
-- charges by default, so the flag-off build is the control.
--   * on the shipped, flag-on ROM (build/ot6.sfc, the suite's default) the
--     cost table is present in bank F0 with kits.md's numbers, so the test
--     asserts the charge and the insufficient-mp refusal.
--   * on the flag-off baseline (ff6/rom/ff6-en-nomp.sfc, handed here via
--     OT6_ROM) the cost table is absent, so the identical SwdTech tech is
--     free.  This is the negative control.

-- The mechanism under test: vanilla's GetMPCost prices only magic/lore/
-- summon/x-magic; Blitz/SwdTech/Tools fall through it at 0, so the universal
-- charge at CalcAttackEffect never fires for them.  Ot6AbilityCost (ot6.asm)
-- swaps that 0 for the kit price keyed by the id in $3a7b.
--
-- On camp_escaped, Cyan is real: katana SWDTECH flag $3BA4 bit 1 reads
-- $82, with Dispatch $55 (4 MP, boost 1) and Retort $56 (10 MP, boost 2)
-- learned. Both scenarios' MP states are the fight's own:
--   charge  the battle's first Cyan turn casts a real Dispatch off the
--           opening 1-bp bank against his real 67-MP pool. ON: debited to
--           exactly mp0-4. OFF: the pool does not move. In both cases the
--           tech lands its hit.
--   refusal (ON only), a labeled isolation arm in two halves: an
--           input-driven route to a broke kit-caster is out of reach on this
--           pool's economy (a deferring party is ground down before real
--           poverty arrives, and a Dispatch walk never spends the pool down
--           because the trash dies first), so the arm keeps the write MP := 1
--           with the pip rebanked by a real item turn.
--           3a, the MENU: with the pool at 1 the SwdTech row is greyed and
--           its confirm is REFUSED (Ot6KitConfirmMP at the tools-shell
--           confirm, mp-economy.md ruling 2) -- it buzzes, the list stays
--           open, no boost is banked and the turn is still CYAN's.
--           3b, the EXECUTION BACKSTOP: with the real pool restored the same
--           Dispatch is committed, and the pool goes broke AT THE LATCH,
--           which is the one seam the universal insufficient-MP fizzle still
--           exists for (an enemy Rasp between the choice and the swing).  The
--           tech must fizzle, dealing no damage, leaving the 1 MP untouched
--           and never negative.  A ladder over
--           fresh battles: the fighting lineage's camp_escaped packs carry
--           a Berserk special, and once it lands on CYAN ($3EE5,x bit 4)
--           CheckPlayerAction (battle_main.asm:1470) auto-picks his turns
--           and his window never opens again in that battle, so an
--           attempt that loses his window is void and drains its battle.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967
local TONIC, POTION = 0xE8, 0xE9
local DISPATCH, DISPATCH_COST = 0x55, 4

local cyan, shadow
local function bp() return H.readByte(0x3E9C + cyan*2) end
local function pend() return H.readByte(0x3E9D + cyan*2) end
local function mp() return H.readWord(0x3C08 + cyan*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function monsterHpSum()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s*2) end
  return t
end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end
local function refindSlots()
  for slot = 0, 3 do
    local id = H.readByte(0x3ED8 + slot*2)
    if id == 0x02 then cyan = slot end
    if id == 0x03 then shadow = slot end
  end
end
-- Can this character's next full gauge open a command window?  The mirror
-- of CheckPlayerAction's status gate (battle_main.asm:1470): STATUS1
-- $3EE4,x {ZOMBIE $02, PETRIFY $40, DEAD $80} and STATUS2 $3EE5,x {BERSERK
-- $10, CONFUSE $20, SLEEP $80} (const.inc STATUS1/STATUS2) each send the
-- turn to CancelAction instead of the menu.  Read, never written.
local ST1_NOMENU, ST2_NOMENU = 0x02 | 0x40 | 0x80, 0x10 | 0x20 | 0x80
local function canMenu(slot)
  return (H.readByte(0x3EE4 + slot*2) & ST1_NOMENU) == 0
     and (H.readByte(0x3EE5 + slot*2) & ST2_NOMENU) == 0
end
local function cyanCanMenu() return canMenu(cyan) end
-- The pack's HP table fills a few frames AFTER battleLoadStarted() and the
-- present mask come up (probe: live at f6670, monster HP at f6671-72), and
-- the status bytes above are the previous battle's until then.  So "CYAN
-- lost his window" is only read off a battle whose pack has HP.
local function cyanLostMenu()
  return monsterHpSum() > 0 and not cyanCanMenu()
end
-- A live ally whose turns the game picks for him (BERSERK or CONFUSE) can
-- swing at the monsters with no pad input at all, so the no-damage half of
-- the refusal cannot be isolated while one is on the field.
local function allyAutoActing()
  for slot = 0, 3 do
    if hp(slot) > 0 and (H.readByte(0x3EE5 + slot*2) & 0x30) ~= 0 then
      return slot
    end
  end
  return nil
end
local function packStr()
  local parts = {}
  for _, id in ipairs(H.monsterIds()) do
    if id ~= 0xFFFF then parts[#parts + 1] = string.format("%03x", id) end
  end
  return table.concat(parts, ",")
end
local function cyanStatusStr()
  return string.format("st1=%02x st2=%02x", H.readByte(0x3EE4 + cyan*2),
    H.readByte(0x3EE5 + cyan*2))
end

local mf = 0
local cyanMode = "defer"                 -- "defer" | "item" | "tech:<row>"
local quietA = false                     -- suppress the menu-idle A-mash: it
                                         -- can land on a just-opened window
                                         -- and confirm a bystander's Fight
local function decide()
  if H.readByte(MENU) == 0 then
    if quietA then return {} end
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act == shadow then
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 60 then hurt = true end
    end
    if st == ST_CMD and not hurt then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(shadow, CMD_ITEM)
      local cur = H.readByte(CMDROW + shadow) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + shadow) + H.readByte(0x894F + shadow)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif act == cyan then
    if cyanMode == "defer" then
      btn = (st == ST_CMD) and "x" or "b"
    elseif cyanMode == "item" then
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_ITEM)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        if want == nil then error("bank ran out of items", 0) end
        local cur = H.readByte(0x8947 + cyan) + H.readByte(0x894F + cyan)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    else
      local row = tonumber(cyanMode:match(":(%d)"))
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_SWDTECH)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_TOOLS then
        local cur = H.readByte(KROW + cyan)
        if cur < row then btn = "down"
        elseif cur > row then btn = "up"
        else btn = "a" end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    end
  else
    btn = (st == ST_CMD) and "x" or "b"
  end
  return btn and { [btn] = true } or {}
end
local function frame()
  if H.battleLoadStarted() then
    H.setPad(decide())
    return
  end
  if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
  H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
end
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(frame),
  }, tag)
end

local mode                               -- "on" (charges) | "off" (free)
local spells, mpWrites = {}, {}
local buzzes, confirms = 0, 0            -- $95 / $96, arm 3a's evidence
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end
local R = {}

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),

  H.call(function()
    local sig = { 0x5d, 0x04, 0x5e, 0x0a, 0x5f, 0x0d }   -- Pummel/AuraBolt/Suplex
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, b in ipairs(sig) do
        if H.readRomByte(a + i - 1) ~= b then ok = false break end
      end
      if ok then base = a break end
    end
    if not base then
      mode = "off"
      H.log("OFF build: Ot6AbilityCostTbl absent from bank F0 (dormant)")
      return
    end
    mode = "on"
    local cost, a = {}, base
    while H.readRomByte(a) ~= 0xFF and a < base + 0x200 do
      cost[H.readRomByte(a)] = H.readRomByte(a + 1)
      a = a + 2
    end
    local want = {                        -- kits.md's authored numbers
      [0x5d] = 4,  [0x64] = 99,           -- Blitz:   Pummel, Bum Rush
      [0x55] = 4,  [0x58] = 16, [0x5c] = 99, -- SwdTech: Dispatch, Quadra Slam, Cleave
      [0xaa] = 4,  [0xa8] = 16, [0xa6] = 18, -- Tools:  AutoCrossbow, Drill, Chain Saw
    }
    for id, c in pairs(want) do
      H.assertEq(cost[id], c, string.format("cost table: id $%02x costs %d", id, c))
    end
    H.log("ON build: cost table verified for Blitz + SwdTech + Tools")
  end),

  H.loadState(STATE),
  H.waitFrames(30),
  driveTo(function() return H.battleLoadStarted() end, 25000, "first encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    refindSlots()
    H.assertEq(cyan ~= nil and shadow ~= nil, true,
      "CYAN and SHADOW really fight this")
    H.assertEq(H.readByte(0x3BA4 + cyan*2) & 0x02, 0x02,
      "his real katana carries the SWDTECH flag (read, not written)")
    H.assertEq(bp(), 1, "the opening 1-bp bank pays Dispatch's boost")
    R.mp0 = mp()
    R.g0 = monsterHpSum()
    if mode == "on" then
      H.assertEq(R.mp0 >= DISPATCH_COST, true, "his real pool affords the tech")
    end
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
      emu.callbackType.write, 0x7e3C08 + cyan*2, 0x7e3C08 + cyan*2)
    -- the two menu sounds, for arm 3a's confirm refusal: $95 is magic's error
    -- buzz, $96 the confirm sound the kit window stamps on every A press
    -- BEFORE the affordability gate.  Direct-page stores land in bank $00, so
    -- both the $0000xx and $7e00xx views are counted together.
    for _, base in ipairs({ 0x000000, 0x7E0000 }) do
      emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
        emu.callbackType.write, base + 0x95, base + 0x95)
      emu.addMemoryCallback(function() confirms = confirms + 1 end,
        emu.callbackType.write, base + 0x96, base + 0x96)
    end
    H.log(string.format("cyan slot %d bp=1 mp=%d; monsters %d hp", cyan,
      R.mp0, R.g0))
  end),

  H.call(function() cyanMode = "tech:0" end),
  driveTo(function() return sawSpell(DISPATCH) end, 20000,
    "the real Dispatch reaches $3410"),
  H.call(function() cyanMode = "defer" end),
  -- the charge lands at Ot6ActionEnd, past the tech's whole animation
  H.waitUntil(function() return pend() == 0 end, 900,
    "the tech resolves (pending consumed)", 10),
  H.waitFrames(120),
  H.call(function()
    local left, dmg = mp(), R.g0 - monsterHpSum()
    local seen = {}
    for _, v in ipairs(mpWrites) do seen[v & 0xff] = true end
    H.log(string.format("Dispatch: MP %d -> %d, monster damage %d", R.mp0, left, dmg))
    H.assertEq(dmg > 0, true, "the tech landed its hit (both builds)")
    if mode == "on" then
      H.assertEq(seen[(R.mp0 - DISPATCH_COST) & 0xff], true,
        "ON: the pool was debited to exactly mp0-4 (write watch)")
      H.assertEq(left, R.mp0 - DISPATCH_COST,
        "ON: Dispatch charged exactly its table cost (4)")
    else
      H.assertEq(left, R.mp0,
        "OFF: Dispatch is free -- vanilla behavior, the negative control")
    end
    H.screenshot("mpcost_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. refusal (ON only) --
  -- The labeled isolation arm; see the header.  The pip is still rebanked by
  -- a real item turn (in a fresh battle it is Ot6InitBP's opening 1) and the
  -- attempt is a real menu drive; only the poverty itself is staged.
  --
  -- An attempt is void, not failed, when CYAN loses his window to a status
  -- (the Berserk special; see the header) or the battle ends under it.  The
  -- latch drive has to see both itself: a berserked CYAN never pends, and a
  -- battle his auto-Fights then win parks on the EXP screen, where
  -- battleLoadStarted() still reads the HP table and the quieted idle A
  -- never dismisses it -- the 30000-frame timeout, not a refusal.  A void
  -- attempt drains its battle (idle A back on) so the next one walks to a
  -- fresh encounter.
  H.cond(function() return mode == "on" end, {
    (function()
      local done = false
      local richMp, snap, menuRefused = nil, nil, false
      local steps = {}
      for attempt = 1, 4 do
        steps[#steps+1] = H.cond(function() return done end, {}, {
          driveTo(function()
            return H.battleLoadStarted() and H.monstersPresent() > 0
          end, 30000, "refusal battle (attempt " .. attempt .. ")"),
          H.call(function()
            refindSlots(); cyanMode = "item"
            H.log(string.format(
              "  [refusal arm %d] pack %s; cyan slot %d bp=%d mp=%d %s",
              attempt, packStr(), cyan, bp(), mp(), cyanStatusStr()))
          end),
          driveTo(function()
            return not H.battleLoadStarted() or cyanLostMenu() or bp() >= 1
          end, 40000, "a real item turn rebanks the pip (attempt "
            .. attempt .. ")"),
          H.cond(function()
            return H.battleLoadStarted() and not cyanLostMenu() and bp() >= 1
          end, {
            -- 3a. THE MENU REFUSAL.  Poverty is staged (the isolation write,
            -- waived and labeled) and the attempt then drives the real
            -- SwdTech submenu at a real banked pip.  Since v0.19 the
            -- tools-shell confirm asks Ot6KitConfirmMP whether the caster can
            -- pay the row (btlgfx UpdateMenuState_30 @8809), so the greyed
            -- row buzzes and the window stays open: CYAN keeps the turn and
            -- the pip.  Before v0.19 this same press committed, and the turn
            -- and the pip were gone by the time the fizzle below fired.
            H.call(function()
              richMp = mp()
              H.writeWord(0x3C08 + cyan*2, 1)
              snap = { bp = bp(), pend = pend(),
                       buzzes = buzzes, confirms = confirms }
              spells = {}
              cyanMode = "tech:0"
              quietA = true
              H.log(string.format("  [refusal arm %d] 3a menu: pool %d -> 1, "
                .. "bp=%d pend=%d", attempt, richMp, snap.bp, snap.pend))
            end),
            driveTo(function()
              return not H.battleLoadStarted() or cyanLostMenu()
                  or buzzes > snap.buzzes
            end, 30000, "the broke SwdTech row is confirmed and buzzes "
              .. "(attempt " .. attempt .. ")"),
            H.waitFrames(90),
            H.call(function()
              menuRefused = false
              if H.battleLoadStarted() and not cyanLostMenu()
                 and buzzes > snap.buzzes then
                H.log(string.format("  [refusal arm %d] 3a: state=%02x mp=%d "
                  .. "bp=%d pend=%d buzz(+%d) confirm(+%d) %s", attempt,
                  H.readByte(MSTATE), mp(), bp(), pend(),
                  buzzes - snap.buzzes, confirms - snap.confirms,
                  sawSpell(DISPATCH) and "saw $55" or "quiet"))
                H.assertEq(confirms > snap.confirms, true,
                  "ON: the A press reached the list ($96, stamped before the "
                  .. "gate) -- the buzz is a rejection, not a press that "
                  .. "never arrived")
                H.assertEq(H.readByte(MSTATE), ST_TOOLS,
                  "ON: the SwdTech submenu is still open -- CYAN is still "
                  .. "choosing and the turn is still his")
                H.assertEq(pend(), snap.pend,
                  "ON: no boost was banked -- Ot6BushidoConfirm was never "
                  .. "reached, because the MP gate refused first")
                H.assertEq(bp(), snap.bp,
                  "ON: the pip is still in the bank")
                H.assertEq(mp(), 1,
                  "ON: the 1 MP is untouched, never negative")
                H.assertEq(sawSpell(DISPATCH), false,
                  "ON: and no tech was ever cast")
                H.screenshot("mpcost_on_menu_refused")
                menuRefused = true
              else
                H.log(string.format("  [refusal arm %d] 3a void: live=%s "
                  .. "menuable=%s %s", attempt,
                  tostring(H.battleLoadStarted()), tostring(cyanCanMenu()),
                  cyanStatusStr()))
              end
              -- the real pool back: 3b's poverty is staged at the LATCH
              H.writeWord(0x3C08 + cyan*2, richMp)
              cyanMode = "defer"
              quietA = false
            end),
            -- 3b. THE EXECUTION BACKSTOP.  The universal insufficient-MP
            -- fizzle at CalcAttackEffect is still real code and still
            -- reachable in play -- an enemy Rasp or Osmose between the choice
            -- and the swing -- so it keeps its own arm.  The poverty is
            -- staged AT THE LATCH, which is exactly that seam: the Dispatch
            -- is chosen and committed against a pool that could pay it, the
            -- pool then goes broke under it, and the tech must fizzle for no
            -- damage and leave the 1 MP alone.
            H.cond(function()
              return menuRefused and H.battleLoadStarted() and bp() >= 1
            end, {
              (function()
                local m0, g1, latched, packSeen = nil, nil, false, false
                return H.repeatN(1, {
                  H.call(function()
                    spells = {}
                    cyanMode = "tech:0"
                    -- quiet the idle A-mash NOW, before the latch drive:
                    -- with CYAN at level 13 the fixture's timing drifted so
                    -- a bystander's Fight (a ~68 physical, not a ~280
                    -- Dispatch) could be confirmed by the MENU==0 idle A
                    -- and land inside the damage window, failing the
                    -- fizzled-for-no-damage check.  CYAN's tech still drives
                    -- (cyanMode routes it whenever his menu is open).
                    quietA = true
                  end),
                  -- the fizzled tech has no grant to signal on, so drive on
                  -- the latch (pending banks 1 at the submenu confirm).
                  -- The damage baseline is captured at the latch, and the
                  -- pad goes quiet for the whole bounded window so nothing
                  -- but the fizzle, or its absence, can touch the monsters.
                  -- The drive also ends, unlatched, when the latch can no
                  -- longer come: CYAN lost his window to a status, or the
                  -- pack is dead (the EXP screen, which the quiet A cannot
                  -- dismiss and battleLoadStarted() cannot see past).  Dead
                  -- means seen alive first: a fresh battle's pack reads 0 HP
                  -- for its first frames (see cyanLostMenu).
                  driveTo(function()
                    if not H.battleLoadStarted() then return true end
                    local packHp = monsterHpSum()
                    if packHp > 0 then packSeen = true end
                    if cyanLostMenu() or (packSeen and packHp == 0) then
                      return true
                    end
                    if pend() >= 1 and not latched then
                      latched = true
                      -- the seam: the action is committed, and the pool goes
                      -- broke under it before it resolves (the isolation
                      -- write, waived and labeled).  This is the only way
                      -- left to reach the execution-side gate, now that the
                      -- menu refuses an unaffordable row outright.
                      H.writeWord(0x3C08 + cyan*2, 1)
                      m0 = 1
                      g1 = monsterHpSum()
                    end
                    return latched
                  end, 30000, "the broke Dispatch is latched (attempt "
                    .. attempt .. ")"),
                  H.call(function() cyanMode = "defer" end),  -- quietA already on
                  H.waitFrames(400),
                  H.call(function() quietA = false end),
                  H.call(function()
                    if not H.battleLoadStarted() or not latched then
                      H.log(string.format("  [refusal arm %d] void before the "
                        .. "latch: live=%s menuable=%s monsters %d hp %s",
                        attempt, tostring(H.battleLoadStarted()),
                        tostring(cyanCanMenu()), monsterHpSum(),
                        cyanStatusStr()))
                      return
                    end
                    local left = mp()
                    local auto = allyAutoActing()
                    H.log(string.format(
                      "refused Dispatch: MP %d -> %d, damage since %d, $3410 %s",
                      m0, left, g1 - monsterHpSum(),
                      sawSpell(DISPATCH) and "saw $55" or "quiet"))
                    H.assertEq(left, m0,
                      "ON: too little MP is REFUSED -- the 1 MP is untouched, "
                      .. "never negative")
                    if auto ~= nil then
                      -- the MP half held; the damage half cannot be read
                      -- off a field where the game swings for an ally.
                      -- A fresh battle measures it again.
                      H.log(string.format("  [refusal arm %d] slot %d is "
                        .. "auto-acting (st2=%02x) inside the damage window; "
                        .. "the no-damage half is measured again in a fresh "
                        .. "battle", attempt, auto,
                        H.readByte(0x3EE5 + auto*2)))
                      return
                    end
                    H.assertEq(g1 - monsterHpSum() <= 0, true,
                      "ON: and the refused tech dealt no damage (fizzled)")
                    H.screenshot("mpcost_on_refused")
                    done = true
                  end),
                })
              end)(),
            }, {}),
          }, {}),
          -- a void attempt leaves whatever battle remains; drain it (idle A
          -- back on, so an EXP screen is dismissed and a berserked CYAN's
          -- own swings end a live one) so the next attempt starts from a
          -- FRESH encounter
          H.cond(function() return done end, {}, {
            H.call(function()
              H.log(string.format("  [refusal arm %d] void: live=%s "
                .. "menuable=%s bp=%d mp=%d %s -- draining the battle",
                attempt, tostring(H.battleLoadStarted()),
                tostring(cyanCanMenu()), bp(), mp(), cyanStatusStr()))
              cyanMode = "defer"
              quietA = false
            end),
            driveTo(function() return not H.battleLoadStarted() end, 60000,
              "the failed attempt's battle drains away (attempt "
              .. attempt .. ")"),
            H.waitFrames(240),
          }),
        })
      end
      steps[#steps+1] = H.call(function()
        H.assertEq(done, true,
          "the refusal completed inside one battle within four encounters")
      end)
      return H.repeatN(1, steps)
    end)(),
  }, {}),

  H.logStep(function() return "mpcost A/B complete in " .. mode .. " mode" end),
})
