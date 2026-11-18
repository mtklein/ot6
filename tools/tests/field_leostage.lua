-- @suite slow savestate=wor_leo
-- field_leostage.lua -- Leo's grave scene for every party shape, and a fallen Gogo (#552, docs/design/leo-reveal.md).
--
-- gen_wor_leo saves Thamasa's street before the grave with GOGO first, second, third and fourth in the party's
-- order (wor_leo_pre, wor_leo_pre_slot2/3/4) and in a party of two (RELM, GOGO: wor_leo_pre_two).  From each, the
-- grave examined through the real pad (its tile, face up, A) and every page pressed on.  Asserted at LEO's "I've
-- been watching you" ($0C0D, the screenshot): GOGO (object 12) stands at the stone (54,18) facing the others
-- (down), and every other member stands below him at (54,19), (53,19) or (52,19), each on its own tile, facing up
-- at him; the pages are GOGO's, LEO's, the first reactor's (CELES, TERRA, LOCKE ... in the scene's order), LEO's
-- two; and when the party is the player's again every member's object stands on the leader's tile (54,18): they
-- walked back into him before they were hidden.
-- Then a fallen Gogo: from wor_leo_pre_slot3 -- the declared expedient (tools/state_write_waivers.txt) -- slot
-- 12's HP set to 0 and Wound set, as a lost fight leaves him; the grave shows vanilla's line ($0845) only and the
-- switch stays clear (EventCmd_ee drops him as though absent); the field care raises him through the menu (a
-- Fenix Down or Revivify, H.fieldCare), and the grave plays the scene.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 12
local REC = 0x1600 + 37 * GOGO
local GRAVE = { 54, 18 }
local SPOTS = { ["54,19"] = true, ["53,19"] = true, ["52,19"] = true }
local DLG_VANILLA, DLG_LEO = 0x0845, 0x0C0C
local REACTORS = { 6, 0, 1, 4, 5, 2, 3, 7, 8, 9, 10, 11, 13 }   -- the scene's case order
local function sw() return H.readByte(0x1E9C) & 1 end
local function members()
  local t, active = {}, H.readByte(0x1A6D) & 7
  for ch = 0, 13 do if (H.readByte(0x1850 + ch) & 7) == active then t[#t + 1] = ch end end
  return t
end
local function settled() return H.hasControl() and H.tileAligned() and not H.dialogWaiting() end

-- the grave, examined; `beat` runs once when $0C0D opens
local shown = {}
local function examine(tag, beat)
  local n, last = 0, nil
  return H.withReset(H.seqStep({
    H.navTo(GRAVE[1], GRAVE[2] + 1, { maxFrames = 12000, playBattles = "tactical" }),
    H.navTo(GRAVE[1], GRAVE[2], { maxFrames = 3000 }),
    H.waitUntil(settled, 600, tag .. ": on the grave's tile", 1),
    H.call(function() shown = {}; n = 0 end),
    -- the first page is recorded as it opens, under the held A (the loop below starts after the release)
    -- (stopped as soon as a dialogue window opens, $ba: its A presses would page on through it)
    H.faceAndHoldA("up", function()
      if H.readByte(0x00BA) == 1 then
        if #shown == 0 then shown[1] = H.readWord(0x00D0) & 0x1FFF end
        return true
      end
      return false
    end, 1200, tag .. ": face the grave, A"),
    H.release(),
    H.driveUntil(function()
      n = n + 1
      return n > 30 and settled() and not H.eventRunning()
    end, 9000, {
      H.call(function()
        if H.dialogWaiting() then
          local id = H.readWord(0x00D0) & 0x1FFF
          if id ~= last then
            last = id
            if not (#shown == 1 and shown[1] == id) then shown[#shown + 1] = id end
            if id == DLG_LEO + 1 and beat then beat() end
          end
          H.setPad(n % 8 < 4 and { "a" } or {})
        else
          last = nil
          H.setPad({})
        end
      end),
    }, tag .. ": the grave's event, through"),
    H.release(),
  }), function() n, last = 0, nil end)
end
local function ids() local t = {} for _, id in ipairs(shown) do t[#t + 1] = string.format("$%04X", id) end return table.concat(t, " ") end

local function shape(state, tag)
  local party, at = nil, {}
  return H.seqStep({
    H.loadState(state),
    H.waitFrames(30),
    H.call(function()
      party = members()
      H.assertEq(sw(), 0, tag .. ": the reveal has not played")
      local names = {}
      for _, ch in ipairs(party) do names[#names + 1] = string.format("%d@%d", ch, (H.readByte(0x1850 + ch) >> 3) & 3) end
      H.log(string.format("[leostage] %s: party (char@position) %s", tag, table.concat(names, " ")))
    end),
    examine(tag, function()
      H.screenshot("field_leostage_" .. tag)
      for _, ch in ipairs(party) do
        at[ch] = { x = H.objX(ch), y = H.objY(ch), face = H.readByte(0x087F + 0x29 * ch) }
      end
    end),
    H.call(function()
      local line = {}
      for _, ch in ipairs(party) do
        local a = at[ch]
        line[#line + 1] = string.format("%d (%d,%d) face %d", ch, a.x, a.y, a.face)
      end
      H.log(string.format("[leostage] %s: at the beat %s; pages %s", tag, table.concat(line, ", "), ids()))
      H.assertEq(at[GOGO].x == GRAVE[1] and at[GOGO].y == GRAVE[2], true, tag .. ": GOGO stands at the stone")
      H.assertEq(at[GOGO].face, 2, tag .. ": GOGO faces the others (down)")
      local used = {}
      for _, ch in ipairs(party) do
        if ch ~= GOGO then
          local k = at[ch].x .. "," .. at[ch].y
          H.assertEq(SPOTS[k] == true, true, string.format("%s: member %d stands below the stone (%s)", tag, ch, k))
          H.assertEq(used[k], nil, string.format("%s: member %d has its own tile", tag, ch))
          used[k] = true
          H.assertEq(at[ch].face, 0, string.format("%s: member %d faces GOGO (up)", tag, ch))
        end
      end
      local reactor = nil
      for _, ch in ipairs(REACTORS) do
        for _, m in ipairs(party) do if m == ch and reactor == nil then reactor = ch end end
      end
      local want = { DLG_LEO, DLG_LEO + 1 }
      if reactor ~= nil then
        local k = ({ [6] = 4, [0] = 5, [1] = 6, [4] = 7, [5] = 8, [2] = 9, [3] = 10, [7] = 11, [8] = 12, [9] = 13,
          [10] = 14, [11] = 15, [13] = 16 })[reactor]
        want[#want + 1] = DLG_LEO + k
      end
      want[#want + 1] = DLG_LEO + 2
      want[#want + 1] = DLG_LEO + 3
      local w = {}
      for _, id in ipairs(want) do w[#w + 1] = string.format("$%04X", id) end
      H.assertEq(ids(), table.concat(w, " "), tag .. ": the scene's pages, in order")
      H.assertEq(sw(), 1, tag .. ": the reveal played")
      for _, ch in ipairs(party) do
        H.assertEq(H.objX(ch) == GRAVE[1] and H.objY(ch) == GRAVE[2], true,
          string.format("%s: member %d walked back into the leader (54,18) before the party was hidden", tag, ch))
      end
    end),
  })
end

H.run({ maxFrames = 200000 }, {
  shape("build/states/wor_leo_pre.mss.lua", "slot1"),
  shape("build/states/wor_leo_pre_slot2.mss.lua", "slot2"),
  shape("build/states/wor_leo_pre_slot3.mss.lua", "slot3"),
  shape("build/states/wor_leo_pre_slot4.mss.lua", "slot4"),
  shape("build/states/wor_leo_pre_two.mss.lua", "two"),

  -- ---- a fallen Gogo -----------------------------------------------------------------------------------------
  H.loadState("build/states/wor_leo_pre_slot3.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.writeWord(REC + 0x09, 0)
    H.writeByte(REC + 0x14, H.readByte(REC + 0x14) | 0x80)
    H.log("[leostage] fallen: slot 12's HP := 0, Wound set (declared expedient: what a lost fight leaves)")
  end),
  examine("fallen"),
  H.call(function()
    H.log("[leostage] fallen: pages " .. ids())
    H.assertEq(ids(), string.format("$%04X", DLG_VANILLA), "a fallen GOGO: the grave reads vanilla's line only")
    H.assertEq(sw(), 0, "a fallen GOGO: the switch stays clear")
    H.assertEq(H.readWord(REC + 0x09), 0, "a fallen GOGO: still down")
  end),
  H.fieldCare({ threshold = 1.0, tag = "raise GOGO" }),
  H.call(function()
    H.assertEq(H.readWord(REC + 0x09) > 0 and (H.readByte(REC + 0x14) & 0x80) == 0, true, "the care raised GOGO")
  end),
  examine("raised"),
  H.call(function()
    H.log("[leostage] raised: pages " .. ids())
    H.assertEq(shown[1], DLG_LEO, "raised, GOGO plays the scene")
    H.assertEq(sw(), 1, "and the reveal sets the switch")
    H.log("[leostage] PASS: every party shape stages the scene; a fallen GOGO is not there until raised")
  end),
})
