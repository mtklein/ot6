-- @suite
-- battle_bushido.lua -- v0.5 Bushido submenu (issue #8): SwdTech is a tools-shell
-- SUBMENU, not the vanilla numeral gauge.
--
-- Vanilla SwdTech ran a free bar (btlgfx_main.asm UpdateMenuState_35/37): the
-- counter w7e7b82 climbed one unit every 4 frames, the tech was counter >> 5,
-- and A latched whatever level it happened to show.  OT6 deletes that path
-- (OpenCmdMenuTbl[7] -> _c1_bushido_open) and drives SwdTech through the Tools
-- window shell (menu state $30) exactly as Blitz was converted.  Each row IS a
-- boost level, weakest at TOP.
--
-- issue #38 put a 1-BP FLOOR on every Bushido tech ("the 0 boost ability feels
-- a bit too much like better attack" -- owner, rc1 playtest), so the window is
-- now THREE rows and row i = boost i+1: 1x/2x/3x, no free rung.  The auto
-- window is correspondingly the TOP THREE learned techs, base = max(0,
-- ceiling-2).  Row 3 of the 4x2 wItemList grid is always $ff now.  The stored
-- loadout format did NOT move (still the packed word at $1e1d, four 3-bit
-- fields); word slot 0 is simply never read.
--
-- Ot6BushidoWindow enumerates the <=3 techs into wItemList's LEFT column, plus
-- its MP cost; the confirm (Ot6BushidoConfirm) maps the picked row i back to
-- boost i+1, banks $3e9d = i+1, and latches that rung's tech.  Single-select
-- and enumeration share Ot6BushidoTech's base/ceiling math and Ot6BushidoOblivion
-- so the menu can never offer a tech the latch would not fire.
--
-- Cyan is not recruitable until v0.3, so he is INSTALLED into the opening guard
-- fight the way the balance labs pin state -- every party slot gets CHAR::CYAN
-- ($3ED8), a Bushido-only command list ($202E, stride 12), the weapon SWDTECH
-- flag ($3BA4/$3BA5 bit 1, without which UpdateCmd_02 greys the command out --
-- battle_main.asm:13690), and a pinned $2020 that stands in for his level.
--
-- What is asserted:
--   1. THE NUMERAL GAUGE IS GONE.  Opening SwdTech lands in the tools shell
--      (state $30), never the numeral state $37.
--   2. THE MOVING WINDOW OF THREE, enumerated into wItemList over a sweep of the
--      ceiling (techs known - 1).  base = max(0, ceiling-2); row i = boost i+1 =
--      tech min(base+i, ceiling), packed at wItemList cell i*2 as attack id
--      $55+tech, the right column and every unused row (always row 3) $ff.
--      N = 1,2,3,4,5,6,8 walks the whole window, including the short-learned-set
--      arms where fewer than three rows are emitted; the sliding retires the
--      weakest as N grows.  Costs decode to $55-$5c prices.
--   3. OBLIVION is the window's top rung at full kit: ceiling 7, row 2 (boost 3)
--      -> tech 7 (Cleave, id $5c), reachable while the once-per-battle latch is
--      clear.
--   4. THE NAMES RENDER: the window's techs are drawn (from BushidoName, since
--      AttackName has no $55-$5c entries); the RETIRED techs (Dispatch AND --
--      new under #38 -- Retort, both off the bottom at ceiling 4) are never
--      drawn.
--   5. A ROW BEYOND CURRENT BP CANNOT COMMIT: with 1 bp, confirming row 2
--      (needs 3 bp) buzzes and leaves the menu open.  #38's load-bearing case:
--      at 0 bp even row 0 (the cheapest rung, 1 bp) buzzes -- there is no free
--      Bushido any more.
--   6. CONFIRM RESOLVES: picking row 1 at ceiling 4 banks boost 2, latches
--      Quadra Slam ($58), reaches $3410, chips a slashing-weak guard and reveals
--      the slash class, and the boost is consumed with no +1 regen that turn.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN, ITEMLIST = 0x2020, 0x4005
local ST_TOOLS, ST_BUSHIDO = 0x30, 0x37
local CMD_SWDTECH = 0x07

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }               -- monster slots -> entity offset 8+slot*2
local function SH(s)  return 0x3E38 + (8 + s * 2) end   -- shields
local function TM(s)  return 0x3E88 + (8 + s * 2) end   -- broken timer
local function WKE(s) return 0x3BE0 + (8 + s * 2) end   -- weak elements
local function WKC(s) return 0x3E9C + (8 + s * 2) end   -- weak classes
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed classes
local function MHP(s) return 0x3BFC + s * 2 end
local function ST3(e) return 0x3EF8 + e end

local function bp(s)   return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function inSub()   return H.readByte(MSTATE) == ST_TOOLS end
local function inNumer() return H.readByte(MSTATE) == ST_BUSHIDO end

-- the ACTUAL in-game tech names (ff6/src/text/bushido_name_en.json), numbered
-- the way the window numbers them.  tech 7 (Cleave) is the divine "Oblivion".
local TECH = { [0] = "Dispatch", "Retort", "Slash", "Quadra Slam",
               "Empowerer", "Stunner", "Quadra Slice", "Cleave" }

local OT6_SLASH = 0x01
local QSLAM = 3                       -- Quadra Slam tech index; id $55+3 = $58
local DMG_CAP = 240                   -- a double-dip (Ot6BoostDmg x4) would exceed

-- the moving window packed at each ceiling: WIN[ceiling] = techs at rows 0..n,
-- row i being boost i+1 (#38's 1-BP floor).  A ceiling < 2 emits fewer than
-- three rows (a boost past the ceiling would just duplicate the top tech, so
-- its row is left $ff).  Row 3 of the grid is ALWAYS $ff now.
local WIN = {
  [0] = { 0 },                        -- N=1: one tech, one rung (1x)
  [1] = { 0, 1 },                     -- N=2: both learned techs, 1x/2x
  [2] = { 0, 1, 2 },                  -- N=3: every learned tech reachable
  [3] = { 1, 2, 3 },                  -- N=4: Dispatch retired off the bottom
  [4] = { 2, 3, 4 },                  -- N=5: Retort retired too
  [5] = { 3, 4, 5 },                  -- N=6: Slash retired too
  [7] = { 5, 6, 7 },                  -- N=8: his top three; row 2 = Oblivion
}
-- a few authored prices (kits.md / Ot6AbilityCostTbl), keyed by attack id.
local COST = { [0x55] = 4, [0x58] = 16, [0x5c] = 99 }   -- $5c: the #57 anchor

local actor
local ceiling = 4
local pinBp, bpbank = true, 5
local pinShields, pinHp = true, true
local spells = {}
local sawNumeral = false
local sh0, hp0 = {}, {}

-- battle-font glyphs: 'A'..'Z' = $80.., 'a'..'z' = $9a.. (battle_class.lua's map)
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

local function pinCyan()
  -- issue #4 regression: pin $2020 with a GARBAGE HIGH BYTE, the way InitSkills
  -- really leaves it (a 16-bit `stx` over CountBits's uninitialized high byte).
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, CMD_SWDTECH)         -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)                  -- nobody dies mid-bench
    H.writeWord(0x3C08 + s * 2, 999)                  -- MP high: costs never fizzle
    H.writeWord(0x3C30 + s * 2, 999)                  --   (99 is the dearest row
                                                      --   there can ever be, #57;
                                                      --   sit clear of the edge)
  end
  if actor and pinBp then H.writeByte(0x3E9C + actor * 2, bpbank) end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    H.writeByte(WKE(s), 0)             -- class chips only (no element x2)
    H.writeByte(WKC(s), OT6_SLASH)     -- slashing-weak -> bushido chips
    H.writeByte(TM(s), 0)              -- never broken
    local st3 = ST3(8 + s * 2)
    H.writeByte(st3, H.readByte(st3) | 0x10)   -- stopped: nothing contests
    if pinHp then H.writeWord(MHP(s), 0xF000) end
    if pinShields then H.writeByte(SH(s), 8) end
  end
end
local function pin() pinCyan(); pinGuards() end

-- open the submenu fresh from the command window, watching for the (now dead)
-- numeral state on the way.
local function openSub(tag)
  return H.driveUntil(inSub, 900, {
    H.call(function()
      pin()
      if inNumer() then sawNumeral = true end
      H.setPad({ "a" })
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, tag or "the swdtech submenu opens (tools shell $30)")
end
-- close the submenu back to the command window (B).
local function closeSub()
  return H.driveUntil(function() return not inSub() end, 400, {
    H.call(function() pin(); H.setPad({ "b" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "the submenu closes back to the command window")
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan installed in slot %d (char id $%02x)",
      actor, H.readByte(0x3ED8 + actor * 2)))
  end),

  -- 1. THE NUMERAL GAUGE IS GONE --------------------------------------------
  H.call(function() ceiling = 4 end),
  openSub("swdtech opens as the tools-shell submenu"),
  H.waitFrames(6),
  H.call(function() H.screenshot("bushido_window") end),
  H.call(function()
    H.assertEq(inSub(), true, "SwdTech opened the tools-shell submenu (state $30)")
    H.assertEq(sawNumeral, false, "the vanilla numeral gauge (state $37) never opened")
  end),

  -- 2/3. THE MOVING WINDOW enumerated into wItemList, ceiling by ceiling ------
  --   (already open at ceiling 4 -- assert this one, then sweep the rest)
  H.call(function()
    for _, ceil in ipairs({ 4, 2, 3, 5, 7 }) do
      -- (re)open at this ceiling: for the first (4) we are already in; else
      -- close + reopen below via the driver.  Assertion body is shared.
    end
  end),
  -- inline sweep: each iteration closes, sets ceiling, reopens, asserts.
  H.call(function() H.log("--- window enumeration sweep ---") end),

  -- ceiling 4 (already open)
  H.call(function()
    local function checkWindow(ceil)
      local techs = WIN[ceil]
      for r = 0, 3 do
        local id = H.readByte(ITEMLIST + r * 6)          -- left cell of row r
        local right = H.readByte(ITEMLIST + r * 6 + 3)   -- right cell (always $ff)
        H.assertEq(right, 0xFF, string.format("ceil %d row %d: right column empty", ceil, r))
        if techs[r + 1] then
          local want = 0x55 + techs[r + 1]
          H.assertEq(id, want, string.format(
            "ceil %d row %d (boost %d): %s id $%02x", ceil, r, r + 1, TECH[techs[r + 1]], want))
          H.assertEq(id >= 0x55 and id <= 0x5c, true,
            string.format("ceil %d row %d id in the SwdTech range $55-$5c", ceil, r))
          if COST[id] then
            H.assertEq(H.readByte(ITEMLIST + r * 6 + 1), COST[id],
              string.format("ceil %d row %d: %s costs %d", ceil, r, TECH[techs[r + 1]], COST[id]))
          end
        else
          H.assertEq(id, 0xFF, string.format(
            "ceil %d row %d: no row (#38: three rungs, and fewer when the "
            .. "learned set is short)", ceil, r))
        end
      end
      -- #38's structural closer: the 4th grid row is retired for good.
      H.assertEq(H.readByte(ITEMLIST + 3 * 6), 0xFF, string.format(
        "ceil %d: the 4th window row is always empty (the 0x rung is gone)", ceil))
    end
    _G.__checkWindow = checkWindow
    checkWindow(4)
    H.log("ceiling 4 window {2,3,4} packs Slash/QuadraSlam/Empowerer at 1x/2x/3x")
  end),

  -- 4. NAMES render (from BushidoName); a retired tech is not drawn ----------
  H.call(function()
    H.assertEq(findName(glyphs("Slash")) ~= nil, true, "\"Slash\" is drawn")
    H.assertEq(findName(glyphs("Empowerer")) ~= nil, true, "\"Empowerer\" is drawn")
    H.assertEq(findName(glyphs("Dispatch")), nil,
      "\"Dispatch\" (retired off the bottom at ceiling 4) is NOT drawn")
    H.assertEq(findName(glyphs("Retort")), nil,
      "\"Retort\" is NOT drawn either -- #38's floor retired the 0x rung, so "
      .. "the ceiling-4 window starts at Slash")
  end),

  -- sweep the remaining ceilings: close, set, reopen, check
  closeSub(), H.call(function() ceiling = 0 end), openSub("reopen at ceiling 0"),
  H.waitFrames(4), H.call(function() _G.__checkWindow(0) end),
  closeSub(), H.call(function() ceiling = 1 end), openSub("reopen at ceiling 1"),
  H.waitFrames(4), H.call(function() _G.__checkWindow(1) end),
  closeSub(), H.call(function() ceiling = 2 end), openSub("reopen at ceiling 2"),
  H.waitFrames(4), H.call(function() _G.__checkWindow(2) end),
  closeSub(), H.call(function() ceiling = 3 end), openSub("reopen at ceiling 3"),
  H.waitFrames(4), H.call(function() _G.__checkWindow(3) end),
  closeSub(), H.call(function() ceiling = 5 end), openSub("reopen at ceiling 5"),
  H.waitFrames(4), H.call(function() _G.__checkWindow(5) end),
  closeSub(), H.call(function() ceiling = 7 end), openSub("reopen at ceiling 7"),
  H.waitFrames(4),
  H.call(function()
    _G.__checkWindow(7)
    H.assertEq(H.readByte(ITEMLIST + 2 * 6), 0x5c,
      "ceiling 7 row 2 (boost 3) = tech 7 (Cleave/Oblivion, id $5c) -- the divine top rung")
    H.log("sweep: window slides weakest-out as techs known grows; Oblivion tops the full kit")
  end),

  -- 5. A ROW BEYOND CURRENT BP CANNOT COMMIT --------------------------------
  -- ceiling 4, bp pinned to 1: row 2 (Empowerer, needs boost 3) must buzz.
  closeSub(),
  H.call(function() ceiling = 4; bpbank = 1 end),
  openSub("reopen at ceiling 4, bp 1"),
  H.waitFrames(4),
  H.call(function()
    local slot = actor
    H.writeByte(0x895F + slot, 0)      -- scroll
    H.writeByte(0x8963 + slot, 0)      -- column 0
    H.writeByte(0x8967 + slot, 2)      -- row 2 (boost 3, > 1 bp)
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),
  H.call(function()
    H.assertEq(inSub(), true,
      "confirming a row beyond current bp did not commit -- still in the submenu")
    H.assertEq(pend(actor), 0, "no boost was banked for the refused row")
  end),

  -- 5b. #38: AT 0 BP EVEN THE CHEAPEST ROW BUZZES ---------------------------
  -- The floor's load-bearing case.  Before #38 row 0 was boost 0 and always
  -- committed for free; now row 0 is boost 1 and an empty bank refuses it, so
  -- a 0-pip Cyan's turn is Fight.  The rows still DRAW (all three greyed --
  -- battle_bushidogrey asserts the visual); it is the confirm that refuses.
  closeSub(),
  H.call(function() ceiling = 4; bpbank = 0 end),
  openSub("reopen at ceiling 4, bp 0"),
  H.waitFrames(4),
  H.call(function()
    local slot = actor
    H.writeByte(0x895F + slot, 0)
    H.writeByte(0x8963 + slot, 0)
    H.writeByte(0x8967 + slot, 0)      -- row 0 = boost 1, the cheapest rung
    H.assertEq(H.readByte(ITEMLIST + 0 * 6), 0x57,
      "row 0 still enumerates Slash at 0 bp -- the list is shown, not emptied")
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),
  H.call(function()
    H.assertEq(inSub(), true,
      "0 bp: even row 0 (boost 1) is refused -- there is no free Bushido (#38)")
    H.assertEq(pend(actor), 0, "and nothing was banked")
  end),

  -- 6. CONFIRM RESOLVES: row 1 at ceiling 4 -> boost 2, Quadra Slam ($58) -----
  closeSub(),
  H.call(function()
    ceiling, bpbank = 4, 5
    pinShields = false
  end),
  openSub("reopen at ceiling 4, bp 5"),
  H.waitFrames(4),
  H.call(function()
    -- park the other two Cyans so only the boosted tech moves guard HP
    for _, s in ipairs(PARTY) do
      if s ~= actor then H.writeByte(ST3(s * 2), H.readByte(ST3(s * 2)) | 0x10) end
    end
    pinHp = false
    for _, s in ipairs(GUARDS) do
      H.writeByte(SH(s), 8); H.writeByte(RVC(s), 0)
      sh0[s] = 8; hp0[s] = H.readWord(MHP(s))
    end
    H.assertEq(H.readByte(RVC(GUARDS[1])), 0, "no class revealed before the tech")
    spells = {}
    local slot = actor
    H.writeByte(0x895F + slot, 0)      -- scroll
    H.writeByte(0x8963 + slot, 0)      -- column 0
    H.writeByte(0x8967 + slot, 1)      -- row 1 -> boost 2 -> Quadra Slam
    H.screenshot("bushido_boosted")
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(8),
  H.call(function()
    H.assertEq(pend(actor), 2, "row 1 banked boost 2 ($3e9d = 2)")
    -- stop pinning bp so Ot6ActionEnd's arithmetic is observable
    pinBp = false
  end),
  -- HANDS OFF from here.  The tech is queued; the only thing left to do is let
  -- the fixture tick with the guards still pinned.  The old drive kept pressing
  -- A whenever a menu was open, which after the confirm RE-OPENED the SwdTech
  -- submenu ($30) and parked the battle there forever -- measured: mstate $30,
  -- pend stuck at 2, guard HP untouched for 3000 frames.  (battle_clockwork
  -- documents the same "an open list would pause execution" rule.)
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == 0x55 + QSLAM then return true end end
    return false
  end, 12000, {
    H.call(function() pin() end),
    H.waitFrames(2),
  }, "Quadra Slam reaches $3410"),
  -- keep the fixture ticking while the queued tech resolves.  A bare waitUntil
  -- stops re-pinning the stopped/HP-pinned guards, and with #38's extra 0-bp
  -- refusal pass upstream the resolution lands late enough that the un-pinned
  -- window mattered (observed: 1200 frames with no pin, timeout).  Driving with
  -- pin() alone -- no button presses -- changes nothing about what is asserted.
  H.driveUntil(function() return pend(actor) == 0 end, 3000, {
    H.call(function() pin() end),
    H.waitFrames(2),
  }, "the boosted tech resolves"),
  H.waitFrames(60),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("attack ids that reached $3410: " .. table.concat(ids, " "))
    local sawQslam = false
    for _, v in ipairs(spells) do if v == 0x55 + QSLAM then sawQslam = true end end
    H.assertEq(sawQslam, true, "boost 2 executed Quadra Slam ($58), not Empowerer ($59)")

    local revealed, chipped = false, false
    for _, s in ipairs(GUARDS) do
      local r, sh = H.readByte(RVC(s)), H.readByte(SH(s))
      H.log(string.format("  guard %d: shields %d -> %d, revealed classes $%02x",
        s, sh0[s], sh, r))
      if r & OT6_SLASH ~= 0 then revealed = true end
      if sh < sh0[s] then chipped = true end
    end
    H.assertEq(chipped, true, "the tech chipped a slashing-weak guard's shields")
    H.assertEq(revealed, true, "and revealed the slash class ($01)")

    local dmg = 0
    for _, s in ipairs(GUARDS) do dmg = dmg + (hp0[s] - H.readWord(MHP(s))) end
    H.log(string.format("Quadra Slam dealt %d across both guards", dmg))
    H.assertEq(dmg > 0, true, "the tech actually dealt damage")
    H.assertEq(dmg < DMG_CAP, true,
      "boost bought the tech, not a damage multiplier too")

    H.log(string.format("bp %d -> %d, pending %d", 5, bp(actor), pend(actor)))
    H.assertEq(bp(actor), 3, "boost consumed (5-2) with no regen that turn")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
    H.log("PASSED: SwdTech submenu enumerates the window, greys/refuses by bp, resolves")
    H.screenshot("bushido_resolved")
  end),
})
