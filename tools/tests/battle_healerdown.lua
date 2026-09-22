-- @suite savestate=first_battle
-- battle_healerdown.lua -- a dead opts.healer must not lock the fight
-- driver out of all healing.
--
-- newFightDriver's makePlan gates every item heal and revive on
-- `actor == opts.healer`.  The fix (ot6.lua, the mayHeal block): when no
-- living entity carries the healer's char id, whoever holds an Item row
-- inherits the job.
--
-- This is a focused unit test and stages with sanctioned expedient writes:
--   * the healer's death is POKED (hp=0 + status1 $80, the same pair the
--     engine's own dead_sub/SetStatus1 leaves), because arranging a real
--     targeted kill would couple this test to formation AI luck;
--   * a Fenix Down is ensured in the battle inventory the same way, as the
--     whole five-byte record LoadItemProp builds (itemRecord below) --
--     first_battle's bag holds none, and an id-and-qty poke left the row
--     greyed, so no revive could ever land.
-- Both writes are this file's waiver lines.
--
-- The arm: healer dead -> ANOTHER actor revives them with the Fenix Down.
-- The revive is attributed, not inferred: the write that takes the
-- healer's HP off zero is caught as it lands, beside the action ExecCmd
-- is running at that moment, and that action must be a living party
-- member's Item command using the Fenix Down on the healer, inside a
-- battle whose formation still stands.  A wipe, a battle that ends first,
-- or the field's $FFFF HP table after the battle is none of those.  The
-- old verdict, `hp(healer) > 0`, passed on exactly that: the riders' Item
-- plans parked at state $05 (the old drive ticked the driver every other
-- frame, so each Down was held past the menu's auto-repeat and MagiTek,
-- -, -, Item went 0 -> 3 -> 0), the staged Fenix Down was greyed anyway,
-- the party wiped, and the verdict read party HP 65535,65535,65535,65535
-- on map 19 -- a black screen -- as "back on their feet".
--
-- The drive calls F.frame() once per emulated frame, the way the route's
-- walkers do.  The control -- healer ALIVE keeps the role assignment -- is
-- not re-proven here: every chain generator that passes opts.healer
-- (gen_tunnelarmr's healer=6 among them) exercises it green on every full
-- run.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"

local BCHID, BATTINV = 0x3ED8, 0x2686
local FENIX_DOWN = 0xF0
local CMD_ITEM = 0x01

local function hp(e)    return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function st1(e)   return H.readByte(0x3EE4 + e * 2) end

local function fenixCount()
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == FENIX_DOWN then
      return H.readByte(BATTINV + i * 5 + 3), i
    end
  end
  return 0, nil
end

-- The battle bag's five-byte record for `item` -- id, usage flags,
-- targeting, qty, equippability -- as LoadItemProp (battle_main.asm)
-- builds it from ItemProp at battle start.  An empty row is $FF with
-- usage $80 ("unusable"), so a poke of the id and qty alone leaves a
-- greyed row whose confirm the item window refuses: the old staging did
-- exactly that on first_battle, whose bag holds no Fenix Down.
local function itemRecord(item)
  local base = (H.sym("ItemProp") & 0x3FFFFF) + item * 30
  local b0 = H.readRomByte(base)
  local flags = 0x80
  if (b0 & 0x20) ~= 0 then flags = flags & 0x7F end   -- usable in battle
  if (b0 & 0x10) ~= 0 then flags = flags | 0x20 end   -- can be thrown
  local mask = H.readRomByte((H.sym("ItemTypeMaskTbl") & 0x3FFFFF) + (b0 & 0x07))
  flags = flags | ((mask << 1) & 0xFF)
  local equip = 0xFF
  if (mask & 0x80) == 0 then
    -- a bit per seat, seat 3 highest: set where that actor cannot equip it
    local can = H.readRomWord(base + 1)
    equip = 0
    for x = 6, 0, -2 do
      equip = (equip << 1) | (((can & H.readWord(0x3A20 + x)) ~= 0) and 0 or 1)
    end
  end
  return flags, H.readRomByte(base + 14), equip
end

local function partyUp()
  local n = 0
  for e = 0, 3 do if maxhp(e) > 0 and hp(e) > 0 and hp(e) < 10000 then n = n + 1 end end
  return n
end

local F = nil          -- the driver under test, built once the battle is up
local healerChid, healerEnt = nil, nil
local fenix0 = 0
local inFlight = nil   -- the action ExecCmd last entered
local raise = nil      -- the write that took the healer off 0 HP, and what ran it

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleLoadStarted() end, 3000,
    "the battle is up"),
  H.waitFrames(120),

  H.call(function()
    -- pick the entity in slot 0 as the designated healer, by char id
    healerEnt = 0
    healerChid = H.readByte(BCHID + healerEnt * 2)
    H.assertEq(maxhp(healerEnt) > 0, true, "slot 0 is a real party member")

    -- ensure a Fenix Down exists (expedient write; see header), as the
    -- whole record LoadItemProp builds
    local n, idx = fenixCount()
    if n == 0 then
      for i = 0, 251 do
        if H.readByte(BATTINV + i * 5) == 0xFF then
          local flags, targeting, equip = itemRecord(FENIX_DOWN)
          local was = {}
          for k = 0, 4 do was[#was + 1] = string.format("%02X", H.readByte(BATTINV + i * 5 + k)) end
          H.log(string.format("battle bag row %d was empty (%s)", i, table.concat(was, " ")))
          H.writeByte(BATTINV + i * 5, FENIX_DOWN)
          H.writeByte(BATTINV + i * 5 + 1, flags)
          H.writeByte(BATTINV + i * 5 + 2, targeting)
          H.writeByte(BATTINV + i * 5 + 3, 2)
          H.writeByte(BATTINV + i * 5 + 4, equip)
          H.log(string.format("staged Fenix Down x2 in battle bag row %d: flags $%02X "
            .. "targeting $%02X equip $%02X", i, flags, targeting, equip))
          break
        end
      end
    end
    fenix0 = fenixCount()
    H.assertEq(fenix0 > 0, true, "a Fenix Down is in the battle bag")
    local _, fidx = fenixCount()
    H.assertEq(H.readByte(BATTINV + fidx * 5 + 1) & 0x80, 0,
      "...and usable in battle (its usage flags do not grey it)")

    -- kill the healer (expedient write pair; the engine's own corpse shape)
    H.writeWord(0x3BF4 + healerEnt * 2, 0)
    H.writeByte(0x3EE4 + healerEnt * 2, st1(healerEnt) | 0x80)
    H.assertEq(hp(healerEnt), 0, "the healer is down")
    H.log(string.format("healer = chid %02X in entity %d, killed; fenix=%d",
      healerChid, healerEnt, fenix0))

    -- which action is executing: ExecCmd's X is the actor's entity * 2,
    -- $B5/$B6 its command and attack (the item, for Item), $B8 the
    -- character targets (InitPlayerAction loads them from $3520)
    local exec = H.sym("ExecCmd@battle_code")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xFFFF
      if x < 20 and x % 2 == 0 then
        inFlight = { e = x // 2, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
                     tgt = H.readByte(0xB8), frame = H.frame }
      end
    end, emu.callbackType.exec, exec, exec)
    -- the raise, as it is written: a nonzero byte into the healer's HP
    -- word while the word still reads 0 (either byte, so a raise to 256+
    -- whose low byte is 0 is caught on its high byte)
    local cell = 0x7E3BF4 + healerEnt * 2
    emu.addMemoryCallback(function(_, v)
      if raise ~= nil or v == nil or v == 0 or hp(healerEnt) ~= 0 then return end
      local by = inFlight or {}
      raise = { frame = H.frame, byte = v, by = by.e, cmd = by.cmd, atk = by.atk,
                tgt = by.tgt, execFrame = by.frame,
                byHp = by.e ~= nil and by.e < 4 and hp(by.e) or nil,
                standing = #H.activeSlots(), up = partyUp() }
      H.log(string.format("[test] f%d the healer's HP leaves 0 (byte $%02X) during "
        .. "entity %s's action (ExecCmd f%s: cmd $%02X atk $%02X targets $%02X); "
        .. "that actor has %s HP, %d monster(s) standing, %d party member(s) up",
        H.frame, v, tostring(raise.by), tostring(raise.execFrame), raise.cmd or 0xFF,
        raise.atk or 0xFF, raise.tgt or 0, tostring(raise.byHp), raise.standing, raise.up))
    end, emu.callbackType.write, cell, cell + 1)

    F = H.newFightDriver("healerdown", {
      items = true, healer = healerChid, cure = false,
    })
  end),

  -- drive the fight until someone else raises the healer.  The battle has
  -- to be there for it: a wipe or an ended battle fails here, fast.
  H.driveUntil(function()
    if raise ~= nil then return true end
    if partyUp() == 0 or not H.battleLoadStarted() or #H.activeSlots() == 0 then
      local hps = {}
      for e = 0, 3 do hps[#hps + 1] = tostring(hp(e)) end
      error(string.format("nobody raised the healer before the fight was over: party HP "
        .. "%s (%d up), %d monster(s) standing", table.concat(hps, ","), partyUp(),
        #H.activeSlots()), 0)
    end
    return false
  end, 30000, {
    H.call(function() F.frame() end),
  }, "a surviving actor revives the dead healer (#128)"),

  H.call(function()
    local r = raise
    local rev = r.by
    H.assertEq(rev ~= nil and rev < 4 and rev ~= healerEnt, true,
      string.format("the raise came from another party member's action (entity %s)",
        tostring(rev)))
    H.assertEq(r.cmd == CMD_ITEM and r.atk == FENIX_DOWN, true,
      string.format("...and that action was Item with the Fenix Down (cmd $%02X atk $%02X)",
        r.cmd or 0xFF, r.atk or 0xFF))
    H.assertEq((r.tgt or 0) & (1 << healerEnt) ~= 0, true,
      string.format("...targeting the healer (targets $%02X, healer bit %d)",
        r.tgt or 0, healerEnt))
    H.assertEq(r.byHp ~= nil and r.byHp > 0, true,
      string.format("the reviver (entity %d) was alive as the raise landed (%s HP)",
        rev, tostring(r.byHp)))
    H.assertEq(r.standing > 0, true,
      string.format("the battle was on as the raise landed (%d monster(s) standing)",
        r.standing))
    -- and still is, now
    H.assertEq(H.battleLoadStarted() and #H.activeSlots() > 0, true,
      "the battle is still on at the verdict")
    H.assertEq(hp(healerEnt) > 0 and hp(healerEnt) < 10000, true,
      string.format("the healer is back on their feet (%d HP)", hp(healerEnt)))
    H.assertEq(hp(rev) > 0, true,
      string.format("the reviver is alive at the verdict (%d HP)", hp(rev)))
    local n = fenixCount()
    H.assertEq(n, fenix0 - 1,
      "the revive spent one Fenix Down (count " .. fenix0 .. " -> " .. n .. ")")
    H.log(string.format("PASSED: entity %d's Fenix Down raised the dead designated "
      .. "healer (entity %d) at f%d, %d frames into its ExecCmd, with %d monster(s) "
      .. "standing -- the party is not locked out of its own bag (#128)",
      rev, healerEnt, r.frame, r.frame - r.execFrame, r.standing))
  end),
})
