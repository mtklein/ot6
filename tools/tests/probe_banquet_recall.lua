-- probe_banquet_recall.lua -- READ-ONLY instrument (issue #75/#31): does
-- the banquet's first-question record latch, WHEN does it latch, and does
-- recall's +5 follow it?  Zero state writes; pad input and reads only,
-- plus in-run savestate blobs to replay the same choice point with all
-- three answers.
--
-- WHY THIS EXISTS.  gen_banquet_done's honest rebuild read $0231/2/3 as
-- ALL ZERO right after the first question's +2 landed (runs sn55GdwQ,
-- MAh3rdsY) and concluded the record mechanic might be broken --
-- "recall's +5 cannot be relied on".  The event source says otherwise
-- (event_main.asm:98355-98395): each first-question branch runs
--
--     switch $023N=1  /  add_var 0, 2
--     if_switch $0230=1, skip
--     switch $0230=1  /  switch $023(1+i)=1
--
-- -- the +2 lands BEFORE the record switches execute, so a read that
-- fires the frame var0 crosses its milestone races the latch by a few
-- event ticks.  And the later gen runs that actually DROVE recall paid
-- +5 every time (runs t90KcsXZ, QkbMFqWb, Wl8BCHxI: "recall+break
-- resolved: +36" = espers 31 + recall 5).  $0230 has NO writer outside
-- the three branches and NO clearer anywhere in the ROM, so a stale
-- pre-set $0230 would need a corrupt save, not gameplay.
--
-- THE MEASUREMENT, in one run, from the banquet_dinner_scratch state the
-- generator cuts (dev scratch, not a fixture):
--   1. a WRITE-WATCH on WRAM $1EC6 -- the byte carrying switches
--      $0230-$0237 -- logs every CPU write with its frame, so the latch
--      moment is measured, not inferred;
--   2. drive toast/kefka/doma/celes, blob the FIRST-QUESTION choice, and
--      replay it three times: pick option i, ride to the next prompt,
--      read the record bits SETTLED (expect $0230=1 and $023(1+i)=1);
--   3. from the option-0 arm, drive to RECALL, blob it, and replay three
--      answers: expect +5 for option 0 exactly, +0 for 1 and 2.
--
-- ============================ VERDICT (2026-08-10) ========================
-- DECODE ERROR: NO.  DEFECT: NO.  Measured live (PASS at frame 5388, all
-- nine arms; the run log is the record):
--   * boot: $0230-$0233 all CLEAR -- no stale record entering the dinner;
--   * THE RACE, CAPTURED: for first=1 and first=2 the read taken the
--     frame var0 crosses the +2 milestone shows ALL record bits still 0
--     ($1EC6=20 / 40 -- only the per-question "asked" bit), while the
--     settled read at the next prompt shows the record latched
--     ($1EC6=25 / 49).  first=0 happened to latch by its milestone frame
--     ($1EC6=13) -- which is why the race read is a coin flip, and why
--     the gen saw zeros on some runs and recall paying on others;
--   * settled reads: first=0 -> $0230+$0231; first=1 -> $0230+$0232;
--     first=2 -> $0230+$0233; the other bits stay clear;
--   * recall pays +5/+0/+0 for answers 0/1/2 against a first=0 record --
--     exactly the decoded contract, deterministic;
--   * instrument note: the $1EC6 WRITE-WATCH fired ZERO times even
--     though the byte demonstrably changed -- the event interpreter's
--     switch writes are invisible to Mesen write callbacks here, the
--     same sample-don't-watchpoint caveat as HANDOFF trap 1.  The
--     before/at/settled SAMPLES carry the proof; keep that in mind
--     before trusting any write-watch on event switch bytes.
-- gen_banquet_done's header note is corrected in the same commit: recall
-- IS earnable and deterministic; the gen keeps its recall-robust tier
-- arithmetic anyway (belt and braces costs nothing), but the "may pay 0"
-- claim now names the instrumentation race, not the game.
-- probe_banquet_qa.lua -- which asserted the record from source-reading
-- and booted a fixture that never existed -- is retired by this probe.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/banquet_dinner_scratch.mss.lua"
local function map() return H.mapId() & 0x1ff end
local function var0() return H.readWord(0x1fc2) end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function recbits()
  return string.format("$0230=%d $0231=%d $0232=%d $0233=%d ($1EC6=%02X)",
    sw(0x0230), sw(0x0231), sw(0x0232), sw(0x0233), H.readByte(0x1EC6))
end
local function choiceUp() return H.readByte(0x056f) >= 2 end

-- one choice prompt: steer the cursor to `idx`, confirm, then edge-A
-- until `done` (reads only)
local function pick(idx, done, maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    local d = done()
    if d then H.setPad({}) end
    return d
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if choiceUp() then
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

-- the gen's multi-target choice machine: targets consumed one per RISING
-- edge of choices-up, done on a var0 milestone (reads only)
local function picks(targets, wantAtLeast, maxFrames, what)
  local ph, ti, wasUp = 0, 0, false
  return H.driveUntil(function()
    local want = type(wantAtLeast) == "function" and wantAtLeast() or wantAtLeast
    local d = var0() >= want
    if d then H.setPad({}) end
    return d
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      local up = choiceUp()
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

-- ride to the NEXT choice prompt (a fresh rising edge, so a still-open
-- prompt from the pick above does not satisfy it early)
local function toNextChoice(maxFrames, what)
  local ph, sawDown = 0, false
  return H.driveUntil(function()
    if not choiceUp() then sawDown = true end
    return sawDown and choiceUp()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if choiceUp() then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

local blobA, blobB = nil, nil
local armMilestone = 0          -- first-question / recall choice points
local w0 = nil

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 251, "boot: the dinner table")
    H.assertEq(choiceUp(), true, "boot: the toast choice is up")
    w0 = var0()
    H.log(string.format("[boot] var0=%d (the window score) | %s", w0, recbits()))
    H.assertEq(H.readByte(0x1EC6) & 0x0F, 0,
      "boot: $0230-$0233 all CLEAR entering the dinner -- no stale record")
    -- THE INSTRUMENT: every CPU write to the switch byte, with its frame.
    -- This is what separates "the record never latches" from "the record
    -- latches after the frame the +2 crosses its milestone".
    -- CPU-bus form ($7E1EC6): no nil-argument holes, and ordinary STA
    -- writes (which these are) fire it reliably.  Block moves would not
    -- (HANDOFF trap 1's caveat) -- if no watch line ever appears yet the
    -- settled reads show the bits, that is the block-move signature and
    -- worth saying in the verdict.
    emu.addMemoryCallback(function(addr, value)
      H.log(string.format("[watch] $7E1EC6 <- %02X at f%d (var0=%d)",
        value or -1, H.frame, var0()))
    end, emu.callbackType.write, 0x7E1EC6, 0x7E1EC6)
  end),

  -- the four fixed choices ahead of the questions
  pick(2, function() return var0() >= w0 + 5 end, 6000, "toast (+5)"),
  pick(0, function() return var0() >= w0 + 10 end, 6000, "Kefka (+5)"),
  pick(1, function() return var0() >= w0 + 15 end, 6000, "Doma (+5)"),
  pick(1, function() return var0() >= w0 + 20 end, 6000, "Celes (+5)"),
  toNextChoice(6000, "the first-question prompt"),
  H.waitFrames(30),
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "blob A (first-question choice)")
        blobA = req.blob
        H.log("[blob A] the first-question choice, var0=" .. var0())
      end),
    })
  end)(),

  -- ---- arm 1: each first-question option, record bits read SETTLED ------
  (function()
    local steps = {}
    for i = 0, 2 do
      local loadReq
      steps[#steps + 1] = H.cond(function() return i == 0 end, {}, {
        H.call(function() loadReq = H.requestLoadState(blobA) end),
        H.waitFrames(2),
        H.call(function() H.checkReq(loadReq, "reload blob A") end),
        H.waitFrames(30),
      })
      steps[#steps + 1] = pick(i, function() return var0() >= w0 + 22 end,
        6000, string.format("first question: option %d (+2)", i))
      steps[#steps + 1] = H.call(function()
        H.log(string.format("[first=%d] AT the +2 milestone frame: %s",
          i, recbits()))
      end)
      steps[#steps + 1] = toNextChoice(6000, "ride to the next prompt")
      steps[#steps + 1] = H.call(function()
        H.log(string.format("[first=%d] SETTLED at the next prompt: %s",
          i, recbits()))
        H.assertEq(sw(0x0230), 1,
          string.format("first=%d: $0230 latched (settled)", i))
        H.assertEq(sw(0x0231 + i), 1,
          string.format("first=%d: $023%d latched (settled)", i, 1 + i))
        for k = 0, 2 do
          if k ~= i then
            H.assertEq(sw(0x0231 + k), 0,
              string.format("first=%d: $023%d stays clear", i, 1 + k))
          end
        end
      end)
    end
    return H.cond(function() return true end, steps)
  end)(),

  -- ---- arm 2: from first=0 (the LAST arm ran with... i=2; reload to i=0)
  -- replay blob A, take option 0, then the two re-asks and Espers, and
  -- blob the RECALL prompt
  (function()
    local loadReq
    return H.cond(function() return true end, {
      H.call(function() loadReq = H.requestLoadState(blobA) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "reload blob A for the recall arm") end),
      H.waitFrames(30),
      H.call(function() armMilestone = w0 + 22 end),
      picks({ 0 }, function() return armMilestone end, 6000,
        "first question: option 0 (+2)"),
      H.call(function()
        H.assertEq(var0() >= w0 + 22, true, "the option-0 +2 landed")
      end),
      H.call(function() armMilestone = w0 + 24 end),
      picks({ 0, 1 }, function() return armMilestone end, 6000,
        "one more -> q1 (+2)"),
      H.call(function()
        H.assertEq(var0() >= w0 + 24, true, "the q1 +2 landed")
      end),
      H.call(function() armMilestone = w0 + 26 end),
      picks({ 0, 2 }, function() return armMilestone end, 6000,
        "one more -> q2 (+2)"),
      H.call(function()
        H.assertEq(var0() >= w0 + 26, true, "the q2 +2 landed")
      end),
      H.call(function() armMilestone = w0 + 31 end),
      picks({ 1, 0 }, function() return armMilestone end, 9000,
        "Espers (+5)"),
      H.call(function()
        H.assertEq(var0() >= w0 + 31, true, "the Espers +5 landed")
      end),
      toNextChoice(9000, "the RECALL prompt"),
      H.waitFrames(30),
      H.call(function()
        H.log(string.format("[recall prompt] %s var0=%d", recbits(), var0()))
        H.assertEq(sw(0x0231), 1, "the record says option 0 was first")
      end),
      (function()
        local req
        return H.cond(function() return true end, {
          H.call(function() req = H.requestSaveState() end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(req, "blob B (the recall choice)")
            blobB = req.blob
          end),
        })
      end)(),
    })
  end)(),

  -- ---- arm 3: the three recall answers against the option-0 record ------
  (function()
    local steps = {}
    for j = 0, 2 do
      local loadReq
      local before
      steps[#steps + 1] = H.cond(function() return j == 0 end, {}, {
        H.call(function() loadReq = H.requestLoadState(blobB) end),
        H.waitFrames(2),
        H.call(function() H.checkReq(loadReq, "reload blob B") end),
        H.waitFrames(30),
      })
      steps[#steps + 1] = H.call(function() before = var0() end)
      steps[#steps + 1] = pick(j, function()
        return not choiceUp() and not H.dialogWaiting()
      end, 9000, string.format("recall answer %d", j))
      steps[#steps + 1] = H.waitFrames(90)
      steps[#steps + 1] = H.call(function()
        local delta = var0() - before
        H.log(string.format("[recall=%d] var0 %d -> %d (delta %+d)",
          j, before, var0(), delta))
        H.assertEq(delta, j == 0 and 5 or 0, string.format(
          "recall answer %d pays %s against a first=0 record",
          j, j == 0 and "+5" or "+0"))
      end)
    end
    return H.cond(function() return true end, steps)
  end)(),

  H.call(function()
    H.log("== VERDICT: the record latches (a few frames after the +2 -- see "
      .. "the $1EC6 watch lines), one bit per first choice, and recall "
      .. "pays +5 exactly on the matching answer.  No decode error, no "
      .. "defect; the gen's zero-read was an instrumentation race. ==")
  end),
})
