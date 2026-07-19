-- probe_bio.lua -- the measurement instrument behind battle_vargas's poison
-- proof: drive EDGAR's Tools -> BioBlaster in the real Vargas fight and read
-- out everything the assertion needs.  Asserts nothing; the product is the
-- log.  probe_vargas.lua is the same instrument for the rest of that fight.
--
-- WHAT IT ANSWERED, none of which the sources settle:
--
--  * EDGAR is battle entity 0 (char $04, level 8) and his in-battle command
--    list reads 00/09/FF/01 -- Fight, Tools, --, Item -- so the Tools window
--    is his own, not a poke.  LOCKE is entity 1, TERRA 2, SABIN 3.
--  * The Figaro shop buy is real: field inventory slot 4 holds item $a4 x1,
--    and the battle inventory ($2686, 5 bytes/entry) carries it with flags
--    $C0 = $80 not-usable-as-an-item | $40 tools.  NoiseBlaster $a3 and
--    AutoCrossbow $aa ride slots 5 and 6.  MakeToolsList filters on that $40
--    and PACKS the survivors into wItemList ($7e4005, 3 bytes/entry), so the
--    BioBlaster lands at list entry 0 -- but scan for it, do not assume it.
--  * The $7BC2 walk of a Tools turn: $05 command list -> $2e OpenToolsWindow
--    (five frames: MakeToolsList_00..04 build the list a chunk per frame)
--    -> $01 the open-animation wait ($7BF0 counts down from $20) -> $30
--    tools select, cursor live -> $38 target select -> $2f close -> $05 ->
--    menu down.  Writing the (scroll, col, row) triple at $895F/$8963/$8967
--    lands the cursor with no d-pad walking (_c18470's index arithmetic).
--  * WHY A TOOL CANNOT REACH VARGAS EARLY.  BioBlaster's item targeting is
--    $6a = ONE_SIDE|INIT_GROUP|MULTI_TARGET|ENEMY with $01 MANUAL CLEAR, so
--    the cursor cannot be walked at all; key_target_2's INIT_GROUP branch
--    (btlgfx_main.asm @7875) aims at monster group A ($7B79) and falls
--    through to group B ($7B7B) only when A has no live monster left.  This
--    formation is Ipoohs in A, Vargas alone in B.  Measured over eight tool
--    turns in one fight: target mask $7B7E read $06, $06, $06, $06 (both
--    Ipoohs), $04, $04, $04 (the survivor), and $01 (Vargas) only on turn 8
--    at frame ~9500, once both Ipoohs were dead -- which is why
--    battle_vargas floors the Ipoohs' hp instead of waiting.
--  * THE CHIP, when it finally reaches him: $3410 = $7d, shields 5 -> 4,
--    revealed elements $00 -> $08.  Plain party swings landed on Vargas
--    twice just before it (hp 11600 -> 11573 -> 11551) with the gauge
--    unmoved, which is battle_vargas's negative control.
--
-- IT ALSO FOUND A HARD LOCK, since fixed.  Before ot6.asm's
-- Ot6ToolListIcon_ext gained its `cmp #$00`, opening this window froze the
-- machine: a `plx` between the class-table load and the `beq`/`bmi` guards
-- left them testing the restored X, so a CLASSLESS tool row (BioBlaster is
-- one) reached a bit-walk over a zero byte and spun forever.  Located by
-- sampling the CPU program counter while wedged -- 240 samples, three
-- distinct PCs, all inside $F0:057D..$F0:0584 -- with the battle NMI's frame
-- counter $98 frozen and $7BC2 stuck at $2e.  battle_class.lua had rendered
-- this same window all along and never saw it: its fixture puts the only
-- classless tool in the list's unrendered second row, so the lock lands
-- after the last thing that test looks at.  Confirmed by reverting the fix
-- and re-running it: all 40 of its assertions pass with $98 dead, which is
-- what its new liveness check at the bottom exists to stop.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/vargas_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL   = 0x202E        -- in-battle commands, slot*12 + i*3
local ITEMLIST = 0x4005        -- wItemList (btlgfx_ram.inc:36), stride 3
local BINV     = 0x2686        -- battle inventory, stride 5
local FINV     = 0x1869        -- field inventory ids (menu/item.asm:552)
local FQTY     = 0x1969
local BIO      = 0xA4          -- BioBlaster item id
local CMD_TOOLS = 0x09
local ST_ROOT, ST_TOOLS, ST_TARGET = 0x05, 0x30, 0x38

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function TM(s)  return 0x3E88 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function ALIVE(s) return 0x3AA8 + s * 2 end
local function MST(s) return 0x3EEC + s * 2 end

local edgarE, vSlot, turns = nil, 0, 0
local prev, lastTrace = {}, ""

local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

-- menu-state changes, one line per transition
local function trace()
  local s = string.format("menu=%d actor=%d mstate=$%02X",
    H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE))
  if s ~= lastTrace then
    lastTrace = s
    H.log(string.format("[trace] f%d %s  (nmi$98=%d)", H.frame, s,
      H.readByte(0x0098)))
  end
end

-- monster-side changes, one line per event
local function shot()
  local out = {}
  for s = 0, 2 do
    out[s] = string.format("hp%d sh%d tm%d rv$%02X al%d st$%02X",
      H.readWord(MHP(s)), H.readByte(SH(s)), H.readByte(TM(s)),
      H.readByte(RVE(s)), H.readByte(ALIVE(s)) & 1, H.readByte(MST(s)))
  end
  out.atk = H.readByte(0x3410)
  return out
end
local function watch()
  trace()
  local now = shot()
  for s = 0, 2 do
    if now[s] ~= prev[s] then
      H.log(string.format("[mon] f%d slot%d %s   (atk $%02X)",
        H.frame, s, now[s], now.atk))
      prev[s] = now[s]
    end
  end
  if now.atk ~= prev.atk then
    H.log(string.format("[atk] f%d $3410 = $%02X", H.frame, now.atk))
    prev.atk = now.atk
  end
end

local function dumpInventory()
  for i = 0, 255 do
    local id = H.readByte(FINV + i)
    if id ~= 0xFF then
      H.log(string.format("  field inv[%d] = $%02X x%d%s", i, id,
        H.readByte(FQTY + i), id == BIO and "   <== BIOBLASTER" or ""))
    end
  end
  for i = 0, 15 do
    local id = H.readByte(BINV + i * 5)
    if id ~= 0xFF then
      H.log(string.format("  battle inv[%d] id=$%02X flags=$%02X target=$%02X qty=%d",
        i, id, H.readByte(BINV + i * 5 + 1), H.readByte(BINV + i * 5 + 2),
        H.readByte(BINV + i * 5 + 3)))
    end
  end
end

local function dumpToolsList(tag)
  local parts = {}
  for i = 0, 7 do
    parts[#parts + 1] = string.format("%d:$%02X/q%d/f$%02X", i,
      H.readByte(ITEMLIST + i * 3), H.readByte(ITEMLIST + i * 3 + 1),
      H.readByte(ITEMLIST + i * 3 + 2))
  end
  H.log("[" .. tag .. "] wItemList " .. table.concat(parts, " "))
end

-- _c18470 (btlgfx_main.asm:20152) indexes the list as
-- ((scroll + row) * 2 + col) * 3, so entry i is addressed by writing the
-- triple -- metrics_battle.lua's idiom, no d-pad walking.
local function toolsCursor(slot, itemId)
  for i = 0, 7 do
    if H.readByte(ITEMLIST + i * 3) == itemId then
      H.writeByte(0x895F + slot, 0)
      H.writeByte(0x8963 + slot, i % 2)
      H.writeByte(0x8967 + slot, i // 2)
      return i
    end
  end
  return nil
end
local function pokeCmd(slot, cmd)
  for i = 0, 3 do H.writeByte(CMDTBL + slot * 12 + i * 3, cmd) end
end

local ep = { slot = nil, placed = false, pulses = 0 }
local function pulse()
  pinParty()
  if H.readByte(MENU) == 0 then ep.slot = nil; return nil end
  local slot = H.readByte(ACTOR)
  if slot ~= edgarE then return { "a" } end          -- everyone else: Fight
  if ep.slot ~= slot then ep.slot, ep.placed, ep.pulses = slot, false, 0 end
  ep.pulses = ep.pulses + 1
  if ep.pulses > 40 then
    ep.pulses, ep.placed = 0, false
    H.log("[edgar] watchdog: backing out with B")
    return { "b" }
  end
  local st = H.readByte(MSTATE)
  if st == ST_ROOT then pokeCmd(slot, CMD_TOOLS); return { "a" } end
  if st == ST_TOOLS then
    if not ep.placed then
      ep.placed = true
      turns = turns + 1
      dumpToolsList("turn " .. turns)
      H.log(string.format("[turn %d] f%d BioBlaster at list entry %s",
        turns, H.frame, tostring(toolsCursor(slot, BIO))))
      return nil
    end
    return { "a" }
  end
  if st == ST_TARGET then
    -- what the engine aimed at, BEFORE we confirm: $7B7D character mask,
    -- $7B7E monster mask, $7B7F multi flag (key_target_2, :18266)
    H.log(string.format("[tgt] f%d charMask=$%02X monMask=$%02X multi=%d " ..
      "itemTarget=$%02X", H.frame, H.readByte(0x7B7D), H.readByte(0x7B7E),
      H.readByte(0x7B7F), H.readByte(0x7A84)))
    return { "a" }
  end
  return nil
end

local aPh = 0
H.run({ maxFrames = 40000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
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
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == 0x0103 then vSlot = s end
    end
    prev = shot()
    for s = 0, 2 do
      H.log(string.format("[seed] slot%d sp$%04X %s weak$%02X", s,
        H.readWord(0x57C0 + s * 2), prev[s], H.readByte(WKE(s))))
    end
    for e = 0, 3 do
      local c = H.readByte(0x3ED8 + e * 2)
      H.log(string.format("entity %d: char=$%02X lvl=%d cmds %02X %02X %02X %02X",
        e, c, H.readByte(0x3B18 + e * 2),
        H.readByte(CMDTBL + e * 12), H.readByte(CMDTBL + e * 12 + 3),
        H.readByte(CMDTBL + e * 12 + 6), H.readByte(CMDTBL + e * 12 + 9)))
      if c == 0x04 then edgarE = e end
    end
    H.log("EDGAR entity = " .. tostring(edgarE) .. ", VARGAS slot = " .. vSlot)
    dumpInventory()
  end),

  -- Play it straight: no Ipooh clamp, so the target-group rule above is
  -- what the log actually shows rather than something we engineered around.
  H.driveUntil(function()
    watch()
    return H.readByte(SH(vSlot)) < 5
  end, 30000, {
    H.call(function() H.setPad(pulse() or {}) end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "a BioBlaster reaches VARGAS's gauge"),

  H.call(function()
    H.log(string.format("DONE after %d tool turns: VARGAS sh%d rv$%02X hp%d " ..
      "lastAtk $%02X", turns, H.readByte(SH(vSlot)), H.readByte(RVE(vSlot)),
      H.readWord(MHP(vSlot)), H.readByte(0x3410)))
    H.screenshot("bio_chip")
  end),
})
