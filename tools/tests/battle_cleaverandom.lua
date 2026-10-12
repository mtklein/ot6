-- @suite savestate=cyan_defence slow
-- battle_cleaverandom.lua -- a random SwdTech never picks Cleave, nor a tech
-- Cyan does not know (v0.27, #379).
--
-- Cleave (SwdTech tech 7, attack $5c) is Cyan's divine, and its one gate is
-- a full 3-BP boost (kits.md "Divines").  RandBushido (battle_main.asm)
-- picks a random known tech when Cyan acts on his own -- Muddled, Charmed,
-- at the Colosseum -- and spends no boost.  Vanilla's range is 0..$2020,
-- every tech known, which assumes they are learned in order; since #379
-- Cleave is learned at the Phantom Train farewell, ahead of the techs
-- between, so OT6's range is the run of techs 0..6 he knows (Ot6RandBushidoTop
-- = Ot6BushidoCeil + 1, ot6_divine.asm): Cleave out, and nothing unlearned in.
--
-- Boots cyan_defence (a solo Cyan, L11, beside battle 43's two soldiers on
-- map 120) and engages the soldiers, twice, one arm each:
--   full  all eight learned ($1CF7 := $FF, $2020 := 7): every bound is 7
--         (techs 0..6); vanilla's, or the cap removed, is 8.
--   gap   Dispatch..Quadra Slam and Cleave ($1CF7 := $8F, $2020 := 4, what
--         InitSkills counts from it): every bound is 4 (techs 0..3); the
--         v0.27 cap gave 5, which reaches Empowerer (tech 4), unlearned.
-- Declared unit-test expedients (tools/state_write_waivers.txt), because the
-- Doma defence is the only battle that fields this Cyan beside enemies on
-- cue, it comes before the farewell, and no generated battle Muddles him:
-- the learned set and $2020 as above, MP := 999, both soldiers' HP :=
-- 30,000 (so his own techs do not end the battle before the picks are
-- counted), Muddle ($3EE5 bit 5) set on him again whenever a hit clears
-- it, and his HP put back to his max whenever it falls under half (Muddled,
-- his techs land on himself too: the first run, at 14f02de1, lost him after
-- three picks).  Nothing else is touched: the command, the pick and the
-- attack are the engine's.
--
-- Watched: each RandBushido entry, and the bound RandA takes right after
-- it (A at RandA's entry: the number of techs the pick ranges over), and
-- every Ot6Oblivion entry with Cleave's attack id.  Asserted, per arm, over
-- PICKS random SwdTechs: every bound is the arm's, and no Cleave executed.
-- Old-ROM red and mutant: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_cleaverandom.out) for the full arm;
-- build/attempts/wt/v028-kits/ for the gap arm.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local CYAN, CLEAVE, PICKS = 0x02, 0x5C, 6
local KNOWN = 0x2020

local cyanSlot = nil
local pending, bounds, cleaves, armed = false, {}, 0, false

local function arm()
  local rb, ra = H.sym("RandBushido"), H.sym("RandA")
  emu.addMemoryCallback(function()
    if armed then pending = true end
  end, emu.callbackType.exec, rb, rb)
  emu.addMemoryCallback(function()
    if not pending then return end
    pending = false
    local n = emu.getState()["cpu.a"] & 0xFF
    bounds[#bounds + 1] = n
    H.log(string.format("[crand] f%d random SwdTech %d: RandA's bound %d ($2020 = %d)", H.frame, #bounds, n,
      H.readByte(KNOWN)))
  end, emu.callbackType.exec, ra, ra)
  local ob = H.sym("Ot6Oblivion")
  emu.addMemoryCallback(function()
    if not armed or H.readByte(0x3A7D) ~= CLEAVE then return end
    cleaves = cleaves + 1
    H.log(string.format("[crand] f%d a Cleave executed", H.frame))
  end, emu.callbackType.exec, ob, ob)
end

local function muddled() return (H.readByte(0x3EE5 + cyanSlot * 2) & 0x20) ~= 0 end

local ARMS = {
  { name = "full", learned = 0xFF, known = 7, bound = 7,
    why = "techs 0..6 (Cleave, tech 7, out of reach)" },
  { name = "gap", learned = 0x8F, known = 4, bound = 4,
    why = "techs 0..3 (Cleave out, and Empowerer, tech 4, unlearned, out)" },
}

local steps = { H.waitFrames(20) }
local function add(t) for _, st in ipairs(t) do steps[#steps + 1] = st end end
for ai, A in ipairs(ARMS) do
  add({
    H.loadState(STATE),
    H.waitFrames(30),
    H.call(function()
      if ai == 1 then arm() end
      armed, pending, bounds, cleaves = false, false, {}, 0
    end),
    H.talkToObj(17, "the soldiers: engage", 20000),
    H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function() H.setPad(H.frame % 8 < 4 and { a = true } or {}) end),
    }, "the soldiers: battle starts"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 5),
    H.waitFrames(60),
    H.call(function()
      cyanSlot = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CYAN then cyanSlot = s end end
      H.assertEq(cyanSlot ~= nil, true, "CYAN is in this battle")
      H.writeWord(KNOWN, A.known)
      H.writeByte(0x1CF7, A.learned)
      H.writeWord(0x3C08 + cyanSlot * 2, 999)
      for m = 0, 5 do
        if (H.readByte(0x3AA8 + m * 2) & 1) == 1 then H.writeWord(0x3BFC + m * 2, 30000) end
      end
      H.log(string.format("[crand] arm %s staged: $2020 := %d, $1CF7 := %02X, MP := 999, "
        .. "soldiers' HP := 30000 (declared expedients)", A.name, A.known, A.learned))
      armed = true
    end),
    H.driveUntil(function() return #bounds >= PICKS or not H.battleLoadStarted() end, 90000, {
      H.call(function()
        if H.battleActive() and not muddled() and (H.readByte(0x3EE4 + cyanSlot * 2) & 0xC2) == 0 then
          H.writeByte(0x3EE5 + cyanSlot * 2, H.readByte(0x3EE5 + cyanSlot * 2) | 0x20)
        end
        -- Muddled, his techs land on himself too: his HP is put back to his
        -- max whenever it falls under half, so he lasts for the picks
        local hp, mx = H.readWord(0x3BF4 + cyanSlot * 2), H.readWord(0x3C1C + cyanSlot * 2)
        if H.battleActive() and hp > 0 and hp < mx // 2 then H.writeWord(0x3BF4 + cyanSlot * 2, mx) end
        H.setPad(H.frame % 8 < 4 and { a = true } or {})   -- the menus Muddle leaves him: none; dialogs: A
      end),
    }, "PICKS random SwdTechs (arm " .. A.name .. ")"),
    H.call(function()
      H.setPad({})
      armed = false
      H.log(string.format("[crand] arm %s: %d random SwdTech(s), bounds %s; %d Cleave(s)", A.name, #bounds,
        table.concat(bounds, ","), cleaves))
      H.assertEq(#bounds >= PICKS, true, string.format("arm %s: %d random SwdTechs were picked", A.name, PICKS))
      for i, n in ipairs(bounds) do
        H.assertEq(n, A.bound, string.format("arm %s: random SwdTech %d ranged over %s", A.name, i, A.why))
      end
      H.assertEq(cleaves, 0, "arm " .. A.name .. ": no Cleave executed")
      H.log(string.format("[crand] arm %s PASS", A.name))
    end),
  })
end
add({ H.call(function() H.log("[crand] PASS: a random SwdTech never reaches Cleave, nor a tech he does not know") end) })

H.run({ maxFrames = 240000 }, steps)
