-- gen_vargas.lua -- from vargas_doorstep.mss: fight VARGAS the way the story
-- means him to be fought, ride the reunion, and mint vargas_won.mss on the
-- first controllable frame after it.  The frontier's last rung-2 link.
--
-- THE FIGHT IS TWO PHASES and only the second has SABIN in it.  Measured
-- (probe_vargas.lua): from the opening bell entities 0/1/2 take turns and
-- entity 3 -- SABIN, char $05, level 9 -- never gets a menu.  His turns
-- start after Vargas's own reaction script runs `battle_event $07` at
-- hp <= 10880 and `battle_event $08` at hp <= 10368 (ai_script.asm
-- :4392-4404), which is the beat that blows the trio offstage.  So this
-- clamps his HP under the second gate and lets HIS script fire the
-- transition; nothing about the break gauge is touched.
--
-- THE KILL IS PUMMEL, not damage.  Vargas has 11600 HP and the reaction
-- script answers `if_attack PUMMEL` with `battle_event $09 / kill_monsters
-- ALL, FADE_HORIZONTAL` (ai_script.asm:4385-4388).  Pummel is picked from the
-- v0.3 blitz menu (the Tools window shell in blitz mode): the cursor is
-- written onto its row (resolved attack id $5d) and confirmed.
-- (For the record, measured in probe_vargas: the harness's kill-bit idiom
-- ALSO ends this fight cleanly -- `if_self_dead / boss_death` sits ahead of
-- the Pummel branch at :4382 and fires -- but the scripted finish is the one
-- the story means, so it is the one the fixture is minted through.)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/vargas_doorstep.mss.lua"

local SABIN_E = 3
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30     -- command list; tools-shell blitz list
local CMD_BLITZ = 0x0A                   -- blitz command id (opens the menu)
local CMDTBL, ITEMLIST = 0x202E, 0x4005  -- command cells; wItemList rows
local PUMMEL = 0x5D                       -- resolved attack id of Blitz 0
local aPh = 0
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pinParty()
  for e = 0, 3 do
    H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2))  -- HP = max: no wipe
    -- v0.5: MP costs are LIVE. THE KILL IS PUMMEL (2 MP) via Vargas's reaction
    -- script; an unpinned SABIN whose Pummel fizzles kills him the WRONG way
    -- (HP depletion, not the scripted finish) and the post-fight event never
    -- fires -- advanceStory then hangs. Pin MP (cur+max) so the blitz affords.
    H.writeWord(0x3C30 + e * 2, 99)                          -- max MP
    H.writeWord(0x3C08 + e * 2, 99)                          -- current MP
  end
end
-- Tap A unless SABIN's own command window is up: Vargas's script talks, and
-- a battle dialog blocks the queue until dismissed.
local function tapUnlessSabin()
  pinParty()
  aPh = (aPh + 1) % 8
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then H.setPad({})
  else H.setPad(aPh < 4 and { "a" } or {}) end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the VARGAS scene reaches battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),
  H.logStep(function()
    return string.format("battle 66 up at f%d: VARGAS %d hp, %d shields",
      H.frame, H.readWord(0x3BFC), H.readByte(0x3E40))
  end),

  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 20000, {
    H.call(function()
      if H.readWord(0x3BFC) > 10300 then H.writeWord(0x3BFC, 10300) end
      tapUnlessSabin()
    end),
  }, "SABIN takes the field"),

  -- PUMMEL from the blitz menu: poke Blitz ($0a) into SABIN's command cells,
  -- A to open the tools-shell list, write the cursor onto Pummel's row (its
  -- resolved attack id $5d), A to confirm.
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
       and H.readByte(MSTATE) == ST_CMD
  end, 12000, { H.call(tapUnlessSabin), H.waitFrames(1) }, "SABIN's command list"),
  H.waitFrames(10),
  H.call(function()
    for i = 0, 3 do H.writeByte(CMDTBL + SABIN_E * 12 + i * 3, CMD_BLITZ) end
  end),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),
  H.driveUntil(function()
    return H.readByte(ACTOR) == SABIN_E and H.readByte(MSTATE) == ST_TOOLS
  end, 3000, { H.call(tapUnlessSabin), H.waitFrames(1) }, "the blitz list opens"),
  H.call(function()
    local row = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == PUMMEL then row = i end
    end
    H.assertEq(row ~= nil, true, "Pummel ($5d) is in the rendered blitz list")
    local slot = H.readByte(ACTOR)
    H.writeByte(0x895F + slot, 0)
    H.writeByte(0x8963 + slot, row % 2)
    H.writeByte(0x8967 + slot, row // 2)
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(8),
  H.call(function()
    H.log(string.format("PUMMEL entered at f%d ($3410=$%02X)",
      H.frame, H.readByte(0x3410)))
  end),

  -- ===================================================================== --
  -- The finish, then the reunion: _ca828f resumes after `battle 66` with
  -- `char_party SABIN,1`, hides the NPC, walks everyone back on and ends
  -- `player_ctrl_on` (event_main.asm:20146).  Ride it to a settled field.
  -- ===================================================================== --
  H.driveUntil(function() return not H.battleLoadStarted() end, 12000, {
    H.call(function()
      pinParty()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the fight ends (battle_event $09 / kill_monsters ALL)"),
  H.logStep(function()
    return string.format("VARGAS down at f%d", H.frame)
  end),
  H.advanceStory((function()
    local cnt = 0
    return function()
      local ok = (H.mapId() & 0x1ff) == 98 and H.hasControl()
        and H.tileAligned() and bright() >= 15
        and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 30
    end
  end)(), 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "back on map 98 after the reunion")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    -- SABIN joined for good: char 5's party byte is set
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true,
      "SABIN is in the party ($1855)")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.log(string.format("vargas_won: map=%d at (%d,%d)",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    H.screenshot("vargas_won")
  end),
  H.saveState("vargas_won.mss"),
  H.logStep(function()
    return string.format("vargas_won minted at frame %d", H.frame)
  end),
})
