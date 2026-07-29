-- probe_banquet_qa.lua -- I->J leg development (issue #31): the DINNER
-- Q&A driven to the perfect 93, from the staged banquet_dinner savestate
-- (probe_banquet_circuit.lua) -- var0 arrives at 44 with the toast choice
-- already up.
--
-- The answer key is banquet-decode.md §5.2 steps 4-6 (§4 for the per-
-- answer values).  Every pick is a QUEUE of cursor targets consumed one
-- per rising edge of "choices up" ($056F >= 2 -- the gen_zozo3_clock
-- machinery), terminated on a var0 milestone (add_var runs immediately
-- after the choice's dlg, so the milestone is tight) or a named switch.
-- The one two-2-choice ambiguity ($06FE "one more?" -> $0701 espers) is
-- exactly why targets are a queue and not a single index.
--
-- Challenge (battle 30, Sp Forces x3): rest break -> chase trooper obj
-- $12 at 251 (76,16) -> "Sure" -> kill-bit clear inside its own 7200
-- timer -> assert species $0c2, $1dd1 & $31 == 0, var0 44+5(+36)=85...
-- (queue arithmetic in-line below).  Ends: $007D=1, party TERRA+LOCKE,
-- var0==93, banquet_postqa.mss minted for the exit probe.
--
--   tools/tests/run.sh tools/tests/probe_banquet_qa.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function var0() return H.readWord(0x1fc2) end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- Drive a stretch of chained choice dialogs.  targets = cursor indices,
-- consumed one per RISING edge of choices-up; between choices, edge-A
-- advances text and battles are kill-bit cleared.  done() ends it.
local function picks(targets, done, maxFrames, what)
  local ph, ti, wasUp = 0, 0, false
  return H.driveUntil(function()
    local d = done()
    if d then H.setPad({}) end
    return d
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); wasUp = false; return
      end
      local up = H.readByte(0x056f) >= 2
      if up and not wasUp then ti = ti + 1 end
      wasUp = up
      if up then
        local idx = targets[math.min(ti, #targets)]
        local cur = H.readByte(0x056e)
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

local function atLeast(n)
  return function() return var0() >= n end
end

local function ckpt(name, want)
  return H.call(function()
    H.assertEq(var0(), want, name .. ": var0")
    H.log(string.format("[qa] %-28s var0=%2d f%d", name, var0(), H.frame))
  end)
end

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/banquet_dinner.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 251, "boot: dinner table")
    H.assertEq(var0(), 44, "boot: the window 44")
    H.assertEq(H.readByte(0x056f) >= 2, true, "boot: toast choice up")
  end),

  -- §5.2 step 4: the table, first half
  picks({ 2 }, atLeast(49), 6000, "toast: hometowns (+5)"),
  ckpt("toast", 49),
  picks({ 0 }, atLeast(54), 6000, "Kefka: jail (+5)"),
  ckpt("kefka", 54),
  picks({ 1 }, atLeast(59), 6000, "Doma: inexcusable (+5)"),
  ckpt("doma", 59),
  picks({ 1 }, atLeast(64), 6000, "Celes: one of us (+5)"),
  ckpt("celes", 64),
  picks({ 0 }, atLeast(66), 6000, "first question: q0 (+2, $0231)"),
  H.call(function()
    H.assertEq(sw(0x0231), 1, "$0231 -- q0 recorded as asked-first")
  end),
  picks({ 0, 1 }, atLeast(68), 6000, "one more -> q1 (+2)"),
  ckpt("q1", 68),
  picks({ 0, 2 }, atLeast(70), 6000, "one more -> q2 (+2)"),
  ckpt("q2", 70),
  picks({ 1, 0 }, atLeast(75), 9000, "Espers: gone too far (+5)"),
  ckpt("espers", 75),
  picks({ 0 }, atLeast(80), 9000, "recall: q0 was first (+5)"),
  ckpt("recall", 80),

  -- §5.2 step 5: the rest break and the troopers' challenge
  picks({ 0 }, function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and H.readByte(0x056f) < 2
  end, 9000, "rest break: yes -> control on the floor"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[break] control at (%d,%d) f%d",
      H.fieldX(), H.fieldY(), H.frame))
  end),
  H.chaseTalk(0x12, 9000, "chase the trooper at 251 (76,16)"),
  picks({ 0 }, function() return sw(0x0237) == 1 end, 15000,
    "challenge: Sure -> battle 30 -> clean win (+5)"),
  H.call(function()
    local w, found = H.formationWords(), 0
    for i = 1, 6 do if w[i] == 0x0c2 then found = found + 1 end end
    H.assertEq(found >= 1, true, "battle 30: Sp Forces ($0c2) formation")
    H.assertEq(H.readByte(0x1dd1) & 0x31, 0,
      "battle 30 clean win -- $40/$44/$45 clear")
    H.assertEq(var0(), 85, "challenge +5")
    H.assertEq(sw(0x0237), 1, "$0237 -- challenge latch")
  end),
  -- dismiss the trailing "Just as we thought…" and settle
  (function() local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and H.tileAligned()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
      end),
    }, "challenge tail settles")
  end)(),

  -- back to the table: the (80,20) walk-on re-arm
  H.navTo(80, 20, { maxFrames = 9000, calmFrames = 4 }),
  H.waitUntil(function() return H.readByte(0x056f) >= 2 end, 1200,
    "'Shall we begin again?'", 5),

  -- §5.2 step 6: Yes -> wish -> accompany
  picks({ 0, 1 }, atLeast(90), 12000, "begin again + wish: war's over (+5)"),
  ckpt("wish", 90),
  picks({ 0 }, atLeast(93), 9000, "accompany: Yes on the first ask (+3)"),
  ckpt("accompany", 93),

  -- §5.2 step 7: the Leo intro, the roster rewrite, control as TWO
  H.advanceStory(function()
    return sw(0x007D) == 1 and map() == 251 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, 60000),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x007D), 1, "$007D -- the banquet tail ran")
    H.assertEq(var0(), 93, "var0 == 93 held through the rewrite")
    local n = 0
    for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
    H.assertEq(n, 2, "party COUNT is two (#21 control)")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    -- the forced availability rewrite (event_main.asm:99058-99067)
    H.assertEq(sw(0x02F0), 1, "$02F0 TERRA available")
    H.assertEq(sw(0x02F1), 1, "$02F1 LOCKE available")
    H.assertEq(sw(0x02F2), 1, "$02F2 CYAN available")
    H.assertEq(sw(0x02F4), 1, "$02F4 EDGAR available")
    H.assertEq(sw(0x02F5), 1, "$02F5 SABIN available")
    H.assertEq(sw(0x02F9), 1, "$02F9 SETZER available")
    H.assertEq(sw(0x02F6), 0, "$02F6 CELES unavailable")
    H.assertEq(sw(0x02F3), 0, "$02F3 SHADOW unavailable")
    H.assertEq(sw(0x02F7), 0, "$02F7 STRAGO unavailable")
    H.assertEq(sw(0x02F8), 0, "$02F8 RELM unavailable")
    H.log(string.format("[postqa] control as TWO at 251 (%d,%d) f%d",
      H.fieldX(), H.fieldY(), H.frame))
    H.screenshot("bq_postqa")
  end),
  H.saveState("banquet_postqa.mss"),
  H.logStep(function()
    return string.format("Q&A done: var0=93, $007D=1, party of two, frame %d",
      H.frame)
  end),
})
