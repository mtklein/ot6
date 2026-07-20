-- battle_vargas.lua -- rung 2's boss gate: VARGAS's break gauge, the three
-- chips that are supposed to reach it, and the scripted finish.
--
--   tools/tests/run.sh tools/tests/battle_vargas.lua
--
-- Boots vargas_doorstep.mss (gen_kolts), presses A once into `_ca828f`
-- (npc_prop.asm:4006 -> event_main.asm:19818), rides the scene through
-- `char_party SABIN,0` (:19906) into `battle 66, MOUNTAINS_EXT` (:19909),
-- and asserts:
--
--   1. THE GAUGE IS AUTHORED, not formula.  Vargas ($0103) seeds 5/5 with
--      class-weak $04 = OT6_BLUDG, straight off Ot6ShieldTbl (ot6.asm:2969);
--      both Ipoohs ($014D) seed 2/2 slash-weak.  The formula value for a
--      monster this size would not be 5, so a dropped row fails here first.
--   2. THE ELEMENT ADD IS LIVE.  His weak byte reads $28 = poison|holy.
--      Vanilla gives poison only -- monster_prop.dat +25 = $08 -- and the
--      holy bit is Ot6ElemAddTbl's row (ot6.asm:216), applied at seed time
--      by Ot6ElemAdd.  This is the assertion that fails if that row is ever
--      dropped, mistyped, or applied to the wrong species.
--   3. POISON CHIPS, and only poison does.  Edgar's Tools -> BioBlaster
--      (item $a4; InitTarget_03 subtracts ThrowToolsOffsetTbl to reach
--      attack $7d, battle_main.asm:6495-6584; MagicProp+1 = $08 poison)
--      takes a shield and reveals poison in $3E89.  Its NEGATIVE CONTROL
--      runs first and in the same fight: the party's plain weapon swings
--      are driven onto Vargas until his hp moves, and the gauge is asserted
--      untouched at that moment.  Same actor, same target, one turn apart --
--      only the weapon changes.  This is the payoff of rung 2's discovery
--      arc (the mines tease, the Figaro shop, the Narshe school), and it is
--      the last link in it that had never been watched work.
--   4. HOLY CHIPS.  Sabin's AuraBolt (Blitz 1, skill $5e, element $20) takes
--      a shield AND reveals holy in $3E89 -- the runtime half of the proof
--      main commit 5d00086 deferred to "the vargas-doorstep fixture".  Holy
--      is the ONLY way that shield can move on that turn: it is checked
--      against the recorded skill id, and Sabin is alone on the field.
--   5. BLUDGEONING CHIPS.  Pummel (Blitz 0, skill $5d, OT6_BLUDG per
--      Ot6SkillClassTbl, ot6_class.asm:193) takes another shield and reveals
--      class $04.
--   6. THE FIGHT ENDS TO THE SCRIPT.  Vargas's reaction script
--      (ai_script.asm:4385-4388) answers `if_attack PUMMEL` with
--      `battle_event $09 / kill_monsters ALL, FADE_HORIZONTAL`, and that --
--      not HP, not the gauge -- is what wins.  Asserted by the battle
--      tearing down within a bounded window of the Pummel that caused it.
--
-- WHY THE HP POKE.  This fight is TWO PHASES and the second one is where
-- Sabin exists as a combatant.  Measured: from the opening bell, entities
-- 0/1/2 (Edgar/Locke/Terra) take turns and entity 3 (Sabin, char $05,
-- level 9) NEVER gets a menu -- 9000 frames of it.  His turns start only
-- after Vargas's own reaction script runs `battle_event $07` at hp <= 10880
-- ("Enough!! Off with ya now!") and `battle_event $08` at hp <= 10368
-- (ai_script.asm:4392-4404), which is the beat that blows the trio offstage
-- and leaves the monk alone -- exactly the fight bosses-wob.md describes.
-- So the test clamps his HP to just under the second threshold and lets HIS
-- OWN SCRIPT fire the transition on the party's next landed hit.  Nothing
-- about the gauge is poked: shields, elements, classes and every chip below
-- are the engine's, and Ipooh/Vargas seed values are read before the clamp.
-- Edgar acts in PHASE ONE, which is where proof 3 has to happen.
--
-- WHY THE IPOOH POKE.  A tool cannot reach Vargas while an Ipooh lives, and
-- that is the engine's rule, not ours.  BioBlaster's item targeting byte is
-- $6a = ONE_SIDE|INIT_GROUP|MULTI_TARGET|ENEMY (item_prop +14; TARGET flags
-- in const.inc:1295) -- crucially WITHOUT $01 MANUAL, so the target cursor
-- cannot be walked.  key_target_2's INIT_GROUP branch (btlgfx_main.asm
-- @7875) aims at monster target group A ($7B79) and only falls through to
-- group B ($7B7B) when no live monster is left in A.  This formation puts
-- the two Ipoohs in A and Vargas alone in B: measured, the target mask
-- $7B7E read $06 for the first four BioBlasters, $04 for the next three,
-- and $01 only after both Ipoohs were dead -- eight tool turns and ~9500
-- frames to reach him.  So the Ipoohs are clamped to 1 hp and the party's
-- own swings finish them; nothing about the gauge, the elements or the
-- targeting is touched, and the mask the engine chose is ASSERTED rather
-- than assumed before the chip is credited.
--
-- SABIN'S LEVEL IS ASSERTED, not assumed.  AuraBolt is a level-6 Blitz; if
-- the join level ever drops under it, proof 4 is testing nothing, so the
-- level is a hard assert rather than a comment.
--
-- THIS TEST IS ALSO THE REGRESSION GUARD for the tools-window hard lock
-- fixed in Ot6ToolListIcon_ext (ot6.asm): a `plx` between the class-table
-- load and its `beq`/`bmi` guards left them reading the restored X, so a
-- CLASSLESS tool row (BioBlaster is one) fell into a bit-walk over a zero
-- byte and spun forever with the battle NMI dead.  Proof 3 cannot pass
-- without opening that window on that row, so a regression times out here
-- rather than shipping a freeze.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/vargas_doorstep.mss.lua"

local VARGAS, IPOOH = 0x0103, 0x014D
local OT6_BLUDG, OT6_SLASH = 0x04, 0x01
local HOLY, POISON = 0x20, 0x08
local PUMMEL, AURABOLT = 0x5D, 0x5E
local BIOBLASTER, BIO_ATK = 0xA4, 0x7D  -- item id -> the attack it resolves to
local CMD_TOOLS = 0x09                  -- battle command id (gen_arvis CMDNAME)
local CMD_BLITZ = 0x0A                  -- blitz command id (opens the menu now)
local SABIN_E = 3                       -- entity index SABIN joins into
local EDGAR_E = 0                       -- entity index EDGAR holds (asserted)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD   = 0x05                   -- the command list, cursor live
local ST_TOOLS = 0x30                   -- UpdateMenuState_30, the tools/blitz list
local ST_TGT   = 0x38                   -- UpdateMenuState_38, target select
local CMDTBL   = 0x202E                 -- in-battle commands, slot*12 + i*3
local ITEMLIST = 0x4005                 -- wItemList (btlgfx_ram.inc:36), 3/entry
local BATTINV  = 0x2686                 -- battle inventory, 5 bytes/entry
local MONMASK  = 0x7B7E                 -- monster target mask (key_target_2)

-- monster slot s -> entity offset 8 + 2s (battle_class's map)
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local aPh = 0
local spells, shWrites = {}, {}
local vSlot = 0
local vHp0 = 0                          -- Vargas's seed hp, for the control
local edgarCmds = {}                    -- restored once proof 3 has landed
local toolTurns, nudges, tgtMask = 0, 0, nil

-- Keep the party upright: Vargas hits hard, a wipe ends the run before it
-- has measured anything, and party HP is not what any of this is about.
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

-- metrics_battle's liveness criterion (the hud builder's own): present bit
-- $3AA8 bit0 AND no death/disappear bit in status-1 $3EEC.  A killed Ipooh
-- keeps its presence bit and takes $80 in status, so the presence bit alone
-- would report it alive forever.
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
-- Speed the Ipoohs' deaths WITHOUT killing them ourselves: floor their hp so
-- the party's next landed swing finishes each.  See "WHY THE IPOOH POKE".
local function clampIpoohs()
  for s = 0, 5 do
    if s ~= vSlot and H.readWord(0x57C0 + s * 2) == IPOOH and monsterAlive(s)
       and H.readWord(MHP(s)) > 1 then
      H.writeWord(MHP(s), 1)
    end
  end
end

local function shields() return H.readByte(SH(vSlot)) end
local function snap(t)
  H.log(string.format("[%s] f%d actor=%d mstate=$%02X vHP=%d shields=%d/%d " ..
    "revElem=$%02X revClass=$%02X weakElem=$%02X lastSkill=$%02X",
    t, H.frame, H.readByte(ACTOR), H.readByte(MSTATE), H.readWord(MHP(vSlot)),
    shields(), H.readByte(SMX(vSlot)), H.readByte(RVE(vSlot)),
    H.readByte(RVC(vSlot)), H.readByte(WKE(vSlot)), H.readByte(0x3410)))
end

-- Tap A unless SABIN's own command window is up.  Vargas's script talks
-- ($12 "I tire of this!", $43, $0a) and a battle dialog blocks the whole
-- queue until it is dismissed -- measured, 9000 frames of menu=00/mstate=00
-- with the fight otherwise alive and nothing pressing anything.
local function tapUnlessSabin()
  pinParty()
  aPh = (aPh + 1) % 8
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then
    H.setPad({})
  else
    H.setPad(aPh < 4 and { "a" } or {})
  end
end

-- ------------------------------------------------------------- proof 3 --
-- THE TOOLS LIST IS DRIVEN BY STATE, not by counting presses: $7BC2 is the
-- battle menu state (UpdateMenuState dispatches on it, btlgfx_main.asm
-- :12536), so the machine below only presses in a stable select state and an
-- input can never land in a window that is still opening.  The walk a Tools
-- turn takes, measured: $05 command list -> $2e OpenToolsWindow (five frames
-- of MakeToolsList_00..04 building wItemList) -> $01 the open-animation wait
-- -> $30 tools select -> $38 target select -> $2f close.
--
-- The wanted tool is reached by WRITING the cursor triple, metrics_battle's
-- idiom: _c18470 (btlgfx_main.asm:20152) indexes the list as
-- ((scroll + row) * 2 + col) * 3 over a 2-column grid, so entry i is
-- addressed by scroll 0 / col i%2 / row i//2 with no d-pad walking, no wrap
-- rules and no dependence on where a previous turn left the cursor.  The
-- entries themselves are PACKED (MakeToolsList filters the battle inventory
-- through the $40 tools flag), so the BioBlaster is found by scanning rather
-- than by arithmetic.
local function toolsCursor(slot, itemId)
  for i = 0, 7 do                       -- 4 rows x 2 columns is the window
    if H.readByte(ITEMLIST + i * 3) == itemId then
      H.writeByte(0x895F + slot, 0)     -- scroll
      H.writeByte(0x8963 + slot, i % 2) -- column
      H.writeByte(0x8967 + slot, i // 2)-- row
      return i
    end
  end
  return nil
end

-- Which command window opens is decided the same way battle_class.lua:603
-- decides it: write the wanted command into ALL FOUR of the actor's cells,
-- so whatever row the cursor rests on opens Tools with one press.  The poke
-- is into battle scratch that InitCmdList rebuilds per battle, and the
-- ORIGINAL list is read at seed time and restored after the chip -- Edgar
-- really does own Tools (cell 1), so this can never hand him a command he
-- does not have.
local ep = { slot = nil, placed = false, pulses = 0 }
local function toolPulse()
  pinParty()
  if H.readByte(MENU) == 0 then ep.slot = nil; return nil end
  local slot = H.readByte(ACTOR)
  -- Reset on ANY actor change, before the Edgar test: the menu flag does not
  -- return to 0 between every pair of actors (measured -- actor 2's window
  -- hands straight to actor 0's), so keying the reset off Edgar alone let his
  -- pulse count carry across turns and trip the watchdog on a healthy menu.
  if ep.slot ~= slot then ep.slot, ep.placed, ep.pulses = slot, false, 0 end
  if slot ~= EDGAR_E then return { "a" } end   -- everyone else keeps swinging
  ep.pulses = ep.pulses + 1
  if ep.pulses > 40 then                -- a window that will not commit:
    ep.pulses, ep.placed = 0, false     -- back out and replan.  nudges is
    nudges = nudges + 1                 -- asserted 0 -- a stalled menu path
    return { "b" }                      -- must not pass as a quiet success.
  end
  local st = H.readByte(MSTATE)
  if st == ST_CMD then
    for i = 0, 3 do H.writeByte(CMDTBL + slot * 12 + i * 3, CMD_TOOLS) end
    return { "a" }
  end
  if st == ST_TOOLS then
    if not ep.placed then               -- place once, idle a pulse so the
      ep.placed = true                  -- list redraws under the cursor
      toolTurns = toolTurns + 1
      ep.entry = toolsCursor(slot, BIOBLASTER)
      return nil
    end
    return { "a" }
  end
  if st == ST_TGT then
    tgtMask = H.readByte(MONMASK)       -- what the engine aimed at, recorded
    return { "a" }                      -- BEFORE we confirm it
  end
  return nil                            -- transient open/close: hands off
end

-- One Blitz, driven the way v0.3 makes it a menu: wait for SABIN's command
-- list, poke Blitz ($0a) into all four command cells (the pokeCmd idiom, so
-- whichever row the cursor rests on opens it), A to open.  _c1776b now hands
-- off to the Tools window shell in blitz mode (Ot6BlitzListOpen fills
-- wItemList with the LEARNED blitzes, keyed by the resolved attack id $5D..
-- $64), so the wanted blitz is picked exactly like a tool: scan wItemList for
-- its id, WRITE the cursor triple ($895F/$8963/$8967) to that cell, A to
-- confirm.  The confirm shim (UpdateMenuState_30) subtracts $5D back to the
-- raw index cmd $0a stores -- the same byte UpdateMenuState_3d used to write.
local function blitz(skillId, name)
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
         and H.readByte(MSTATE) == ST_CMD
    end, 12000, { H.call(tapUnlessSabin), H.waitFrames(1) },
      name .. ": SABIN's command list"),
    H.waitFrames(10),
    H.call(function()
      for i = 0, 3 do H.writeByte(CMDTBL + SABIN_E * 12 + i * 3, CMD_BLITZ) end
    end),
    H.pressButtons({ "a" }, 4), H.waitFrames(10),
    H.driveUntil(function()
      return H.readByte(ACTOR) == SABIN_E and H.readByte(MSTATE) == ST_TOOLS
    end, 3000, { H.call(tapUnlessSabin), H.waitFrames(1) },
      name .. ": the blitz list is open (tools-shell state $30)"),
    H.call(function()
      local row = nil
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == skillId then row = i end
      end
      H.assertEq(row ~= nil, true,
        name .. ": listed in the rendered blitz menu (wItemList)")
      local slot = H.readByte(ACTOR)
      H.writeByte(0x895F + slot, 0)         -- scroll
      H.writeByte(0x8963 + slot, row % 2)   -- column
      H.writeByte(0x8967 + slot, row // 2)  -- row
      snap(name .. " window")
    end),
    H.waitFrames(2),                        -- let the list redraw under the cursor
    H.pressButtons({ "a" }, 4),
    H.waitFrames(8),
  })
end

local nBefore = 0                       -- gauge-write count before a chip

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "booted on map 98, VARGAS's ledge")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing him")
  end),

  -- ONE interaction -> the scene -> battle 66
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
  -- 1 + 2: the seed.  Read BEFORE anything is poked or pressed.
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

    -- THE ELEMENT ADD.  vanilla = poison only; OT6 adds holy.
    local weak = H.readByte(WKE(vSlot))
    H.log(string.format("VARGAS weak elements = $%02X (vanilla $08 + add $20)", weak))
    H.assertEq(weak & POISON, POISON, "poison bit (vanilla, monster_prop +25)")
    H.assertEq(weak & HOLY, HOLY,
      "HOLY bit present -- Ot6ElemAddTbl's $0103 row applied (ot6.asm:216)")
    H.assertEq(weak, POISON | HOLY, "weak byte is exactly poison|holy")

    -- SABIN, and the level AuraBolt needs
    H.assertEq(H.readByte(0x3ED8 + SABIN_E * 2), 0x05,
      "SABIN is battle entity " .. SABIN_E)
    local lv = H.readByte(0x3B18 + SABIN_E * 2)
    H.log("SABIN joins at level " .. lv)
    H.assertEq(lv >= 6, true,
      "SABIN is level 6+ so AuraBolt is learned (got " .. lv .. ")")

    -- EDGAR, his Tools command, and the weapon proof 3 needs.  The
    -- BioBlaster is VERIFIED IN INVENTORY, not assumed off the Figaro shop
    -- route: the battle inventory ($2686, 5 bytes/entry) is scanned for item
    -- $a4, and its $40 tools flag is what MakeToolsList filters on, so a
    -- shop route that ever stops selling it fails HERE with a clear message
    -- instead of hanging in a menu that has no such row.
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
  -- 3a: THE NEGATIVE CONTROL for the poison chip.  Clear the Ipoohs out of
  -- the tool's target group (see "WHY THE IPOOH POKE") and keep swinging
  -- until a PLAIN weapon hit has moved Vargas's hp.  Nobody in this party
  -- carries a poison, holy or bludgeoning weapon, so the gauge must not have
  -- moved -- which is the assertion.  Without it, "the shield went down
  -- after Edgar acted" would be equally explained by "anything that hits him
  -- takes a shield", and proof 3 would be worth nothing.
  -- ===================================================================== --
  H.driveUntil(function()
    return ipoohsDown() and H.readWord(MHP(vSlot)) < vHp0
  end, 24000, {
    H.call(function()
      clampIpoohs()
      tapUnlessSabin()
    end),
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
  -- 3b: POISON.  Edgar, one turn later, at the same target, changes only the
  -- weapon: Tools -> BioBlaster.
  -- ===================================================================== --
  -- the pred runs every frame, the body once per 30 (one pulse of 6 pad
  -- frames then 24 idle, metrics_battle's cadence), so the party pin lives
  -- in the pred: Vargas can burst a character down inside a single pulse.
  H.driveUntil(function()
    pinParty()
    return #shWrites > 0
  end, 20000, {
    H.call(function() H.setPad(toolPulse() or {}) end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "the BioBlaster reaches VARGAS's gauge"),
  H.call(function()
    snap("after BIOBLASTER")
    for i = 0, 3 do
      H.writeByte(CMDTBL + EDGAR_E * 12 + i * 3, edgarCmds[i])
    end
    H.log(string.format("tool turns: %d, cursor entry: %s, target mask: $%02X",
      toolTurns, tostring(ep.entry), tgtMask or 0xFF))
    H.assertEq(ep.entry ~= nil, true,
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
  -- Into phase two: clamp Vargas under his own script's second threshold
  -- and let the party's hits fire battle_event $07 / $08.  The gauge is
  -- untouched; only HP moves, and only downward past a scripted gate.
  -- ===================================================================== --
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 20000, {
    H.call(function()
      if H.readWord(MHP(vSlot)) > 10300 then H.writeWord(MHP(vSlot), 10300) end
      tapUnlessSabin()
    end),
  }, "SABIN takes the field (battle_event $07/$08 ran)"),
  H.call(function()
    H.assertEq(H.readByte(SH(vSlot)), 4,
      "the gauge reads 4 -- phase one moved HP, and exactly one shield")
    H.assertEq(#shWrites, 1,
      "and exactly ONE gauge write in all of phase one: the BioBlaster's")
    snap("phase two")
    H.screenshot("vargas_phase2")
  end),

  -- ===================================================================== --
  -- 4: HOLY.  AuraBolt (Blitz 1, resolved attack id $5e) picked from the menu.
  -- ===================================================================== --
  H.call(function() nBefore = #shWrites end),
  blitz(AURABOLT, "AURABOLT"),
  H.driveUntil(function() return #shWrites > nBefore end, 2400, {
    H.call(tapUnlessSabin),
  }, "AURABOLT reaches the gauge"),
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
  -- 5 + 6: BLUDGEONING, and the finish.  Pummel (Blitz 0, resolved attack id
  -- $5d) picked from the menu.  Vargas answers `if_attack PUMMEL` with
  -- battle_event $09 + kill_monsters ALL, so this same selection is both the
  -- class proof and the win path; the shield write and the teardown are
  -- asserted separately.
  -- ===================================================================== --
  H.call(function() nBefore = #shWrites end),
  blitz(PUMMEL, "PUMMEL"),
  H.driveUntil(function() return #shWrites > nBefore end, 2400, {
    H.call(tapUnlessSabin),
  }, "PUMMEL reaches the gauge"),
  H.call(function()
    snap("after PUMMEL")
    H.assertEq(H.readByte(0x3410), PUMMEL, "the resolved skill was Pummel ($5d)")
    H.assertEq(shields(), 2, "PUMMEL took a shield: 3 -> 2")
    H.assertEq(H.readByte(RVC(vSlot)) & OT6_BLUDG, OT6_BLUDG,
      "and REVEALED the bludgeoning class ($04)")
    H.assertEq(H.readByte(RVE(vSlot)), POISON | HOLY,
      "both elements stay revealed across the class chip")
  end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 9000, {
    H.call(function()
      pinParty()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the fight ends (battle_event $09 / kill_monsters ALL)"),
  H.call(function()
    H.assertEq(H.battleLoadStarted(), false, "battle torn down after PUMMEL")
    H.log(string.format("PASSED with VARGAS at %d HP -- the script killed him, " ..
      "not the damage", 11600 - 10300))
    H.log("skill writes: " .. #spells .. ", gauge writes: " .. #shWrites)
    for i = 1, #shWrites do
      H.log(string.format("  gauge f%d -> %d", shWrites[i][1], shWrites[i][2]))
    end
    H.screenshot("vargas_won")
  end),
})
