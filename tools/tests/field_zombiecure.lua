-- @suite savestate=thamasa_night
-- field_zombiecure.lua -- #190: field care cures Zombie with a Revivify.
--
-- Zombie ($02 in status 1) persists out of battle and Remedy's mask leaves
-- it (item.asm @8bb2: $65), and CARE_STATUS_CURES had no row for it, so a
-- zombied member walked from care stop to care stop untouched and into the
-- next fight attacking the party; the Vector crash site's fight driver then
-- spent eight Fenix Downs on two of them that never raised (#220).  The row
-- is Revivify, and the status pass now skips only the dead, which is
-- CheckCanUseItem's own shape: the wound branch takes a Fenix Down and
-- nothing else, every other cure item checks its own bit (item.asm
-- @8b8e-@8bbb), and the $C2 mask belongs to the heals (@8bc4).  The old
-- pass skipped every $C2 member, so its petrify row could never fire
-- either; branch C is that row, now live.
--
-- The fixture is thamasa_night: the world tile outside Thamasa, TERRA LOCKE
-- SHADOW, and two Revivifies already in the bag (the route never bought
-- one and no care stop ever reached for one).
--
-- WHAT IS STAGED, AND IT IS ONE BYTE.  A Zombie is a monster special's roll
-- (special $41, monster_prop.dat +$1F: Orog, Osteosaur, FossilFang,
-- Bloompire, Ogor, Zombone, Exoray, Uroburos, Wizard, Black Drgn,
-- Necromancr, Tiger, Hidonite; of the 164 field maps the seeded route
-- walked, only the Sealed Gate cave's 384 and 385 pool one, Zombone); it
-- cannot be had on cue, and no shipped fixture carries one because the
-- exit contract refuses it (M.standing).  The bit is written onto LOCKE's
-- status 1 once per branch, from the boot snapshot, and nothing else in
-- this file writes emulated state: the plan, the menu walk, the item's
-- acceptance, the bag delta and the cleared bit are the game's, read back.
--
-- Three branches from the snapshot:
--   A. Zombie, Revivify in the bag: the visit plans "cure zombie" for LOCKE
--      before anything else, the game accepts the Revivify, the bit clears,
--      the bag drops by one, and no Fenix Down moves.
--   B. Zombie, the Revivifies reserved away (opts.reserve): nothing is
--      spent, the bit stays, and the roster line names the cure the bag
--      would not offer -- a zombie is never a Fenix Down's business.
--   C. Petrify, Soft in the bag: the petrify row fires the same way.
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE = 0x01
local REVIVIFY, SOFT, FENIX = 0xF1, 0xF4, 0xF0
local ZOMBIE, PETRIFY = 0x02, 0x40

-- every line the lib logs, for assertions on what the visit said
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end
local function forget() lines = {} end

local function statusAddr(c) return 0x1600 + 37 * c + 20 end

-- the one staged byte: `bit` onto LOCKE's status 1
local function stage(bit, what)
  return H.call(function()
    local st = H.charStatus1(LOCKE)
    H.assertEq(st & bit, 0, what .. ": LOCKE does not carry the bit before the write")
    H.writeByte(statusAddr(LOCKE), st | bit)
    H.assertEq(H.charStatus1(LOCKE), st | bit, what .. ": the bit is set")
    H.log(string.format("[%s] staged: char %d status1 %02X -> %02X", what,
      LOCKE, st, H.charStatus1(LOCKE)))
  end)
end

local blob, req, before
local function remember()
  return H.call(function()
    before = { revivify = H.invCountOf(REVIVIFY), soft = H.invCountOf(SOFT),
               fenix = H.invCountOf(FENIX), hp = H.charHp(LOCKE) }
    forget()
  end)
end
local function reload(what)
  return H.cond(function() return true end, {
    H.call(function() req = H.requestLoadState(blob) end),
    H.waitFrames(2),
    H.call(function() H.checkReq(req, what) end),
  })
end
local RESERVE_B = {}   -- filled once the bag is read: every Revivify held back

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/thamasa_night.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "booted on the world map outside Thamasa")
    H.assertEq(H.worldX(), 249, "world x")
    H.assertEq(H.worldY(), 128, "world y")
    H.assertEq(H.invCountOf(REVIVIFY) >= 1, true, "Revivify in the bag")
    H.assertEq(H.invCountOf(SOFT) >= 1, true, "Soft in the bag")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charStatus1(c) & (ZOMBIE | PETRIFY), 0,
        string.format("char %d carries neither bit at boot", c))
    end
    RESERVE_B[REVIVIFY] = H.invCountOf(REVIVIFY)
    H.log(string.format("[boot] revivify=%d soft=%d fenix=%d", H.invCountOf(REVIVIFY),
      H.invCountOf(SOFT), H.invCountOf(FENIX)))
    req = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(req, "boot snapshot"); blob = req.blob end),

  -- A
  stage(ZOMBIE, "A"),
  remember(),
  H.fieldCare({ tag = "A" }),
  H.call(function()
    H.assertEq(said("[A] plan: cure zombie char 1 with $F1"), true,
      "A: the visit plans the cure")
    H.assertEq(said("[A] used $F1 on char 1"), true,
      "A: the game accepted the Revivify")
    H.assertEq(H.charStatus1(LOCKE) & ZOMBIE, 0, "A: the Zombie bit is cleared")
    H.assertEq(H.invCountOf(REVIVIFY), before.revivify - 1, "A: one Revivify spent")
    H.assertEq(H.invCountOf(FENIX), before.fenix, "A: no Fenix Down spent")
    H.assertEq(said("[A] plan: revive"), false, "A: no revive was planned")
    H.log(string.format("[A] LOCKE %d -> %d hp across the cure", before.hp, H.charHp(LOCKE)))
  end),

  -- B
  reload("boot snapshot reload for B"),
  stage(ZOMBIE, "B"),
  remember(),
  H.fieldCare({ tag = "B", reserve = RESERVE_B }),
  H.call(function()
    H.assertEq(said("[B] plan:"), false, "B: nothing planned")
    H.assertEq(said(string.format("zombie: revivify %d in the bag, floor %d",
      before.revivify, before.revivify)), true,
      "B: the roster names the cure the bag would not offer")
    H.assertEq(H.charStatus1(LOCKE) & ZOMBIE, ZOMBIE, "B: the Zombie bit stays")
    H.assertEq(H.invCountOf(REVIVIFY), before.revivify, "B: no Revivify spent")
    H.assertEq(H.invCountOf(FENIX), before.fenix, "B: no Fenix Down spent")
  end),

  -- C
  reload("boot snapshot reload for C"),
  stage(PETRIFY, "C"),
  remember(),
  H.fieldCare({ tag = "C" }),
  H.call(function()
    H.assertEq(said("[C] plan: cure petrify char 1 with $F4"), true,
      "C: the visit plans the cure")
    H.assertEq(said("[C] used $F4 on char 1"), true, "C: the game accepted the Soft")
    H.assertEq(H.charStatus1(LOCKE) & PETRIFY, 0, "C: the Petrify bit is cleared")
    H.assertEq(H.invCountOf(SOFT), before.soft - 1, "C: one Soft spent")
    H.assertEq(H.invCountOf(FENIX), before.fenix, "C: no Fenix Down spent")
  end),
})
