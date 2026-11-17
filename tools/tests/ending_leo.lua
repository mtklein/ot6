-- @manual splice: tools/tests/gen_wor_kefka.lua with ENDING_LEO = { reveal = false }
-- ending_leo.lua -- the ending's Gogo and the revealed Leo (#552, docs/design/leo-reveal.md).  An instrument.
--
-- Not a script of its own: spliced into gen_wor_kefka (the line's last leg: Kefka, then the ending) right after
-- its lib line, behind ENDING_LEO = { reveal = true|false }, and run from the leg's battery:
--   reveal = false   the battery as the line saved it (GOGO a mystery): the cast card reads "<his name> as Gogo"
--                    (the small name the record's, written to $7E9E89 by DrawEndingCharName; the big name
--                    EndingCharNameAnim row 12) and his scene after it (map 254) draws slot 12 in his sprite
--                    and palette;
--   reveal = true    the battery staged as after the reveal (tools/tests/ending_leo_stage.py: switch $00E0 set,
--                    slot 12's name LEO, graphics $10, field palette 0, the stats and max HP Ot6LeoReveal writes --
--                    a declared state write, never route evidence): the card reads "LEO as Gogo" (owner, 2026-11-17: the small name from the
--                    record, vanilla's big "Gogo" over the cloaked art), and his scene draws Leo's sprite ($10)
--                    in Leo's palette (0).
-- A recruited member gets no portrait vignette (only one never recruited does), so neither run reads one.
-- Why an instrument, not a suite: each run plays gen_wor_kefka's whole leg (the final battle, the ending:
-- ~177,000 frames), and the revealed run needs a staged battery no graph leg makes (the line never plays the
-- reveal: it is a branch); qualification proves it composes and starts (check_instruments.py).
-- It writes nothing.  It counts those ROM reads, shoots the cast card (EndingState_46 and after) and his scene,
-- and asserts when the run reaches The End
-- ($bb).  Run:
--   python3 -c 'import sys; sys.path.insert(0,"tools"); import check_instruments as c; \
--     print(c.splice(open("tools/tests/gen_wor_kefka.lua").read(), "ENDING_LEO = { reveal = true }\n" + \
--     open("tools/tests/ending_leo.lua").read()))' > build/lab/ending_leo_reveal.lua
--   python3 tools/tests/ending_leo_stage.py       # -> build/lab/ck/wor-kt-plates-v1
--   OT6_SRAM_CHECKPOINT=build/lab/ck/wor-kt-plates-v1 tools/tests/run.sh build/lab/ending_leo_reveal.lua <log>
ENDING_LEO = ENDING_LEO or { reveal = false }
do
  local E = { name = {}, portrait = {}, shotAt = {}, cards = 0, maps = {} }
  ENDING_LEO.seen = E
  local function shoot(tag, after)
    for _, d in ipairs(after) do E.shotAt[#E.shotAt + 1] = { f = H.frame + d, tag = string.format("%s_f%d", tag, d) } end
  end
  local armed = false
  local function arm()
    if armed then return end
    armed = true
    local nameTbl = H.sym("EndingCharNameAnim")
    -- the small name: the six bytes DrawEndingCharName writes for the card (vanilla's path, by actor $0C)
    emu.addMemoryCallback(function(a, v)
      if E.cards > 0 and E.small == nil then E.smallBuf = E.smallBuf or {} end
      if E.smallBuf and #E.smallBuf < 6 then E.smallBuf[#E.smallBuf + 1] = string.format("%02X", v) end
    end, emu.callbackType.write, 0x7E9E89, 0x7E9E8E)
    for _, row in ipairs({ 12 }) do
      local at = nameTbl + row * 6
      emu.addMemoryCallback(function() E.name[row] = (E.name[row] or 0) + 1 end, emu.callbackType.read, at, at + 1)
    end
    local pp = H.sym("PortraitGfxPtrs@field_code")
    for _, row in ipairs({ 12, 16 }) do
      local at = pp + row * 2
      emu.addMemoryCallback(function()
        E.portrait[row] = (E.portrait[row] or 0) + 1
        if E.portrait[row] == 1 then shoot("ending_leo_vignette" .. row, { 60, 240, 420 }) end
      end, emu.callbackType.read, at, at + 1)
    end
    local s46 = H.sym("EndingState_46")
    emu.addMemoryCallback(function()
      E.cards = E.cards + 1
      shoot("ending_leo_card", { 90, 300, 520 })
    end, emu.callbackType.exec, s46, s46)
    emu.addEventCallback(function()
      local m = H.mapId() & 0x1FF
      -- his scene follows his card (event_main.asm: `ending 70`, then map 254 with SETZER, EDGAR and CELES)
      if m == 254 and E.cards > 0 and not E.maps[254] then
        E.maps[254] = H.frame
        shoot("ending_leo_scene", { 120, 400, 700, 1000, 1400 })
      end
      if E.maps[254] and E.gfx == nil and H.frame >= E.maps[254] + 120 then
        E.gfx = H.readByte(0x0879 + 41 * 12)
        E.pal = H.readByte(0x0880 + 41 * 12) & 0x0E
      end
      for i = #E.shotAt, 1, -1 do
        if H.frame >= E.shotAt[i].f then H.screenshot(E.shotAt[i].tag); table.remove(E.shotAt, i) end
      end
    end, emu.eventType.endFrame)
    H.log(string.format("[ending_leo] armed: reveal %s; switch $00E0 = %d, slot 12 graphics $%02X", tostring(
      ENDING_LEO.reveal), H.readByte(0x1E9C) & 1, H.readByte(0x1601 + 37 * 12)))
  end
  local function judge()
    local small = table.concat(E.smallBuf or {}, " ")
    local want = {}
    for i = 2, 7 do want[#want + 1] = string.format("%02X", H.readByte(0x1600 + 37 * 12 + i)) end
    want = table.concat(want, " ")
    H.log(string.format("[ending_leo] reveal %s: the card's small name %s (slot 12's record %s)", tostring(
      ENDING_LEO.reveal), small, want))
    H.assertEq(small, want, "the card's small name is slot 12's record name")
    if ENDING_LEO.reveal then H.assertEq(small, "8B 84 8E FF FF FF", "the card's small name is LEO") end
    H.log(string.format("[ending_leo] reveal %s: cast card ran %d time(s); big name row 12 (Gogo) read %d; his "
      .. "scene (map 254 after the card): object 12 graphics $%02X palette $%02X; vignette "
      .. "portrait 12 (Gogo) read %d, $10 (Leo) read %d", tostring(ENDING_LEO.reveal), E.cards, E.name[12] or 0,
      E.gfx or -1, E.pal or -1, E.portrait[12] or 0, E.portrait[16] or 0))
    H.assertEq(E.cards > 0, true, "the ending ran Gogo's cast card")
    H.assertEq((E.name[12] or 0) > 0, true, "the cast card's big name is row 12, \"Gogo\"")
    H.assertEq(E.gfx, ENDING_LEO.reveal and 0x10 or 0x0C, "his scene draws slot 12 in " .. (ENDING_LEO.reveal
      and "Leo's" or "Gogo's") .. " sprite")
    H.assertEq(E.pal, ENDING_LEO.reveal and 0x00 or 0x06, "in " .. (ENDING_LEO.reveal and "Leo's" or "Gogo's")
      .. " palette")
    -- the portrait vignette plays for a member never recruited (event_main.asm: `if_switch $02FC=0` to it, and
    -- after a recruited member's scene `if_switch $0127=0` past it, a switch nothing sets): this battery has GOGO
    -- recruited, so neither portrait is read; Ot6LeoPortrait's remap stands for the day that path is reached
    H.assertEq((E.portrait[12] or 0) + (E.portrait[16] or 0), 0, "no portrait vignette for a recruited member")
    H.log("[ending_leo] PASS")
  end
  -- arm at the leg's boot (the Continue), judge at The End: the leg's own log line for $bb is its last word
  local boot = H.bootCheckpoint
  H.bootCheckpoint = function(key, opts)
    return H.seqStep({ boot(key, opts), H.call(arm) })
  end
  local saveState = H.saveState
  H.saveState = function(name, ...)
    if name == "wor_kefka.mss" then return H.seqStep({ H.call(judge), saveState(name, ...) }) end
    return saveState(name, ...)
  end
end
