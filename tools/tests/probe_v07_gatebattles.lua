-- probe_v07_gatebattles.lua -- PROBE-FIRST evidence for the Sealed Gate set
-- pieces, issue #31's "decode and drive battles 121/122 and 123".  NOT a
-- suite test.
--
-- WHY IT FORCES THE BATTLES INSTEAD OF WALKING TO THEM.  Reaching the gate
-- room means crossing map 384 -- ten mod_bg_tiles sites, seven face+A
-- switches and two teleport pairs (recon §1 leg 3) -- which is the leg the
-- 385 timed floor currently blocks.  The three questions #31 asks (real
-- contents vs dummy formation, loseability, what the H->I gen must know)
-- are answerable without the walk, because they are properties of the
-- BATTLE, and the field engine's own `battle` opcode is one RAM write:
--     $0011E0 = battle index, $0011E2/3 = bg, $0011E4 = ?, $078A = flags,
--     $56 = 1  -- exactly what EventBattle does (ff6/src/field/event.asm
--     :1909-1941), and what the Phantom-Train ride does from ASM with no
--     event opcode at all (gen_n128.lua's header).
-- The event-battle GROUP -> battle-index mapping is decoded from
-- ff6/src/field/event_battle_group.dat (4 bytes per group, two candidate
-- indices, 3/4 and 1/4): group 121 -> 384, 122 -> 385, 123 -> 386 (both
-- candidates identical in all three, so the roll cannot vary the fight).
--
-- WHAT THE OFFLINE READ SAYS, so the live run can contradict it.
-- battle_monsters.dat records are FIFTEEN bytes, not 26 and not 20
-- (battle_main.asm:8123-8128 computes index*16 - index), laid out
-- byte1 = present-bitfield, bytes 2-7 = monster id LOW bytes, 8-13 =
-- positions, byte14 = id HIGH bits.  Under that layout:
--     battle 384/385/386 = ONE monster, species $17b, in slot 0
--     battle 387 (Ultros III) = $12e, battle 524 (Ninja) = $003
--     battle 70 = $00e, $00e, $008  <- THREE, which is the fight recon §11
--                                      says the offline read got wrong;
--                                      the error there looks like a record
--                                      STRIDE, not lying data
-- Species $17b has HP 1 (monster_prop.dat +8..9) and an AI script that is
-- nothing but a battle-id dispatcher (ai_script.asm:8061-8086):
--     target_off SELF                      <- untargetable, every fight
--     if battle $0180 (=384): battle_event $13, kill_monsters MONSTER_1
--     if battle $0181 (=385): battle_event $14, end_battle
--     if battle $0182 (=386): battle_event $15, end_battle
-- i.e. no attack command exists anywhere in it.  THIS PROBE IS THE CHECK ON
-- THAT: it records the live formation, the party's HP across the whole
-- fight, and how (and after how many frames) each battle ends, pressing
-- NOTHING but edge-A and never kill-bitting.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

local function hpLine()
  local hp = {}
  for i = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + i * 2)) end
  return table.concat(hp, "/")
end
local function monsterLine()
  local t = {}
  for i = 0, 5 do
    local id = H.readWord(0x3F46 + i * 2)
    local hp = H.readWord(0x3BFC + i * 2)
    t[#t + 1] = string.format("%04X:hp%d", id, hp)
  end
  return table.concat(t, " ")
end

-- Force one event battle exactly as EventBattle does, then watch it.
-- NOTHING is kill-bitted and no direction is ever pressed: A is edge-tapped
-- only, so anything that happens to the party is the battle's own doing.
local function forceBattle(idx, label)
  local t0, seen, maxSeen, ended = 0, nil, 0, nil
  local hp0 = nil
  return H.seqStep({
    H.call(function()
      hp0 = { H.readWord(0x1609), H.readWord(0x1609 + 37),
              H.readWord(0x1609 + 74), H.readWord(0x1609 + 111) }
      H.log(string.format("[%s] forcing event battle index %d from map %d "
        .. "(%d,%d); field party TERRA=%d LOCKE=%d EDGAR=%d SABIN=%d",
        label, idx, map(), H.fieldX(), H.fieldY(),
        partyOf(0), partyOf(1), partyOf(4), partyOf(5)))
      H.writeByte(0x078A, 0x00)
      emu.write(0x11E0, idx & 0xFF, emu.memType.snesMemory)
      emu.write(0x11E1, (idx >> 8) & 0xFF, emu.memType.snesMemory)
      emu.write(0x11E2, H.readByte(0x0522) & 0x7F, emu.memType.snesMemory)
      emu.write(0x11E3, 0x00, emu.memType.snesMemory)
      emu.write(0x11E4, 0x00, emu.memType.snesMemory)
      H.writeByte(0x56, 1)
      t0 = H.frame
    end),
    H.waitUntil(function() return H.battleLoadStarted() end, 1200,
      label .. ": battle loads", 1),
    H.waitUntil(function() return H.battleActive() end, 900,
      label .. ": battle renders", 15),
    H.call(function()
      local w = H.formationWords()
      H.log(string.format("[%s] LIVE formation %04X %04X %04X %04X %04X %04X",
        label, w[1], w[2], w[3], w[4], w[5], w[6]))
      H.log(string.format("[%s] monsters: %s", label, monsterLine()))
      H.log(string.format("[%s] party battle HP: %s", label, hpLine()))
      H.screenshot("v07gb_" .. label .. "_up")
    end),
    -- ride it: edge-A only, no kill-bit, no directions.  Sample the party
    -- HP every 60 frames so a fight that CAN hurt shows up as a drop.
    (function()
      local ph, n, minHp = 0, 0, 9999
      return H.driveUntil(function() return not H.battleLoadStarted() end,
        12000, {
        H.call(function()
          ph = (ph + 1) % 8
          n = n + 1
          for i = 0, 3 do
            local v = H.readWord(0x3BF4 + i * 2)
            if v > 0 and v < minHp then minHp = v end
          end
          if n % 120 == 0 then
            H.log(string.format("[%s] f+%d monsters=%s party=%s minHP=%d",
              label, n, monsterLine(), hpLine(), minHp))
          end
          H.setPad(ph < 4 and { "a" } or {})
        end),
      }, label .. ": ride the set piece to its own end")
    end)(),
    H.call(function()
      ended = H.frame - t0
      H.log(string.format("[%s] battle ENDED after %d frames; "
        .. "b-switch $40=%d $44=%d $45=%d", label, ended,
        (H.readByte(0x1E80 + (0x1E0 >> 3)) >> 0) & 1, 0, 0))
      -- the battle switches proper: $3EC0-region b-switches are read by
      -- if_b_switch; log the raw bytes so the H->I gen can see them
      local bs = {}
      for a = 0x1DD0, 0x1DDF do bs[#bs + 1] = string.format("%02X", H.readByte(a)) end
      H.log(string.format("[%s] $1DD0..DF = %s", label, table.concat(bs, " ")))
    end),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
    end, 6000, label .. ": field control back", 5),
    H.waitFrames(60),
    H.call(function()
      local hp1 = { H.readWord(0x1609), H.readWord(0x1609 + 37),
                    H.readWord(0x1609 + 74), H.readWord(0x1609 + 111) }
      H.log(string.format("[%s] FIELD HP before %d/%d/%d/%d after %d/%d/%d/%d "
        .. "-- map %d (%d,%d)", label, hp0[1], hp0[2], hp0[3], hp0[4],
        hp1[1], hp1[2], hp1[3], hp1[4], map(), H.fieldX(), H.fieldY()))
      H.screenshot("v07gb_" .. label .. "_after")
    end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/v07q_385_entry.mss.lua"),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 385, "booted in the Sealed Gate cave (map 385)")
    H.assertEq(partyOf(0x00), 1, "TERRA is in the party (the gate roster)")
    H.assertEq(partyOf(0x01), 1, "LOCKE is in the party")
    H.log("[probe] forcing the three set pieces in play order")
  end),
  forceBattle(384, "battle121"),
  forceBattle(385, "battle122"),
  forceBattle(386, "battle123"),
  H.logStep("gate-battle probe complete"),
})
