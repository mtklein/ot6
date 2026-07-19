-- probe_vargas.lua -- the measurement instrument behind battle_vargas: walk
-- the Mt. Kolts scene into `battle 66` and read out everything the fight is
-- made of, asserting nothing.  Its job is to answer the questions the
-- sources alone do not: what slot Vargas seeds into, what his gauge and
-- element/class rows actually read after Ot6SeedShields and Ot6ElemAdd have
-- run, what LEVEL Sabin joins at (AuraBolt is a level-6 Blitz, so the holy
-- proof stands or falls on it), and what the two candidate win paths do.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/vargas_doorstep.mss.lua"

local VARGAS_SPECIES = 0x0103
local IPOOH_SPECIES  = 0x014D
-- monster slot s -> entity offset 8 + 2s (battle_class's map)
local function SH(s)  return 0x3E38 + (8 + s * 2) end   -- current shields
local function SMX(s) return 0x3E39 + (8 + s * 2) end   -- max shields
local function TM(s)  return 0x3E88 + (8 + s * 2) end   -- broken timer
local function RVE(s) return 0x3E89 + (8 + s * 2) end   -- revealed elements
local function WKE(s) return 0x3BE0 + (8 + s * 2) end   -- weak elements
local function WKC(s) return 0x3E9C + (8 + s * 2) end   -- class weaknesses
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed classes
local function MHP(s) return 0x3BF4 + (8 + s * 2) end   -- current hp
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local SABIN_E = 3                      -- entity index SABIN joined into
local spells, shWrites = {}, {}

-- keep the party upright while we drive: Vargas hits hard and a wipe ends
-- the probe before it has measured anything.  Current HP <- max HP, every
-- frame, for the four party entities (offset 2e; max at $3C1C).
local function pinParty()
  for e = 0, 3 do
    H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2))
  end
end

local function dumpCmds()
  for e = 0, 3 do
    H.log(string.format("  entity %d char=$%02X cmds %02X %02X %02X %02X",
      e, H.readByte(0x3ED8 + e * 2),
      H.readByte(0x2019 + e * 12), H.readByte(0x201A + e * 12),
      H.readByte(0x201B + e * 12), H.readByte(0x201C + e * 12)))
  end
end

local function report()
  H.log("$3410 writes (last spell used): " .. #spells)
  for i = math.max(1, #spells - 8), #spells do
    H.log(string.format("   [%d] $%02X", i, spells[i]))
  end
  H.log("$3E40 (VARGAS shields) writes: " .. #shWrites)
  for i = math.max(1, #shWrites - 12), #shWrites do
    H.log(string.format("   f%d -> %d", shWrites[i][1], shWrites[i][2]))
  end
end

local function slots()
  local out = {}
  for s = 0, 5 do out[s] = H.readWord(0x57C0 + s * 2) end
  return out
end
local function findSlot(species)
  for s = 0, 5 do
    if H.readWord(0x57C0 + s * 2) == species then return s end
  end
  return nil
end

local function dumpMonsters(tag)
  local w = slots()
  H.log(string.format("[%s] f%d formation %04X %04X %04X %04X %04X %04X",
    tag, H.frame, w[0], w[1], w[2], w[3], w[4], w[5]))
  for s = 0, 5 do
    if w[s] ~= 0xFFFF then
      H.log(string.format(
        "  slot %d species %04X: shields %d/%d timer %02X hp %d " ..
        "weakElem %02X revealedElem %02X weakClass %02X revealedClass %02X",
        s, w[s], H.readByte(SH(s)), H.readByte(SMX(s)), H.readByte(TM(s)),
        H.readWord(MHP(s)), H.readByte(WKE(s)), H.readByte(RVE(s)),
        H.readByte(WKC(s)), H.readByte(RVC(s))))
    end
  end
end

local function dumpParty(tag)
  H.log("[" .. tag .. "] party:")
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      -- $1600+14/15/16 are the three "spells/blitzes known" bitmask bytes
      H.log(string.format(
        "  char %2d actor=%02X level=%2d hp=%d/%d  known %02X %02X %02X",
        c, H.readByte(base), H.readByte(base + 8),
        H.readWord(base + 9), H.readWord(base + 11),
        H.readByte(base + 14), H.readByte(base + 15), H.readByte(base + 16)))
    end
  end
  -- battle-side: which entity is whose, and what commands they hold
  for e = 0, 3 do
    H.log(string.format("  entity %d: char=%02X cmds %02X %02X %02X %02X level=%d",
      e, H.readByte(0x3ED8 + e * 2),
      H.readByte(0x2020 + e * 12), H.readByte(0x2021 + e * 12),
      H.readByte(0x2022 + e * 12), H.readByte(0x2023 + e * 12),
      H.readByte(0x3B18 + e * 2)))
  end
end

local aPh = 0
H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("booted map=%d at (%d,%d) facing=%d",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803))))
    dumpParty("doorstep")
  end),

  -- ===================================================================== --
  -- One interaction: the party is already standing at (22,32) facing RIGHT
  -- at VARGAS (map 98's only NPC, object 16, `set_npc_event _ca828f`,
  -- npc_prop.asm:4006).  A -> dialogs $00F8..$00FC -> `char_party SABIN,0`
  -- (event_main.asm:19906) -> `battle 66, MOUNTAINS_EXT` (:19909).
  -- ===================================================================== --
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "VARGAS scene -> battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),

  H.call(function()
    dumpMonsters("seed")
    dumpParty("in battle")
    H.log("VARGAS slot = " .. tostring(findSlot(VARGAS_SPECIES)))
    H.log("IPOOH slot  = " .. tostring(findSlot(IPOOH_SPECIES)))
    H.screenshot("vargas_seed")
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    emu.addMemoryCallback(function(_, v)
      shWrites[#shWrites + 1] = { H.frame, v }
    end, emu.callbackType.write, 0x7E3E40, 0x7E3E40)
  end),

  -- ===================================================================== --
  -- INTO PHASE TWO.  Measured here and recorded because no source says it:
  -- from the opening bell entities 0/1/2 take turns and entity 3 (SABIN)
  -- NEVER gets a menu -- 9000 frames of it.  His turns begin only after
  -- Vargas's own reaction script runs `battle_event $07` at hp <= 10880 and
  -- `battle_event $08` at hp <= 10368 (ai_script.asm:4392-4404), the beat
  -- that blows the trio offstage.  Clamp his HP under the second gate and
  -- let his script do the rest.
  -- ===================================================================== --
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 20000, {
    H.call(function()
      if H.readWord(0x3BFC) > 10300 then H.writeWord(0x3BFC, 10300) end
      pinParty()
      aPh = (aPh + 1) % 8
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then
        H.setPad({})
      else
        H.setPad(aPh < 4 and { "a" } or {})
      end
    end),
  }, "SABIN takes the field"),
  H.call(function()
    dumpMonsters("phase two")
    H.log(string.format("SABIN's menu at f%d (actor=%d mstate=$%02X)",
      H.frame, H.readByte(ACTOR), H.readByte(MSTATE)))
    H.screenshot("vargas_phase2")
  end),

  -- ===================================================================== --
  -- THE KILL-BIT QUESTION.  The harness's standard way to end a fight is to
  -- set $3EEC+off bit7 on every live monster (H.clearBattle).  Vargas's
  -- reaction script opens with `if_self_dead / boss_death` (ai_script.asm
  -- :4382-4384) BEFORE the `if_attack PUMMEL` branch, so what a kill bit
  -- does to a boss whose death is scripted was an open question.  It is
  -- asked here, once, and whatever it answers is logged rather than
  -- assumed -- battle_vargas.lua does not depend on it either way, because
  -- the Pummel path is proven and is the one the story means.
  -- ===================================================================== --
  H.call(function()
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
      end
    end
    H.log("kill bits set on every live monster slot")
  end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 6000, {
    H.call(function()
      pinParty()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
      if H.frame % 600 == 0 then
        H.log(string.format("kill-bit watch f%d: batt=%s monsters=%d " ..
          "vHP=%d shields=%d", H.frame, tostring(H.battleLoadStarted()),
          H.monstersPresent(), H.readWord(0x3BFC), H.readByte(0x3E40)))
      end
    end),
  }, "kill-bit teardown"),
  H.call(function()
    H.log(string.format("KILL-BIT VERDICT: battle ended at f%d (batt=%s)",
      H.frame, tostring(H.battleLoadStarted())))
    H.screenshot("vargas_killbit")
  end),
  H.waitFrames(300),
  H.call(function()
    H.log(string.format("after teardown: map=%d ctl=%s field=(%d,%d)",
      H.mapId() & 0x1ff, tostring(H.hasControl()),
      H.fieldX(), H.fieldY()))
  end),
})
