-- @suite
-- battle_breakwob_events.lua -- the World of Balance event fights the v0.45 design audit found on the generated
-- floor, re-verified from the built ROM (battle_breakwob_train's shape: pure ROM bytes, no savestate).
-- docs/design/break-coverage-wob.md sections 13-18 are the design; the tables below are its, and the only place
-- the expectations live.
--
--   1. each designed species carries exactly its Ot6ShieldTbl row and keeps its vanilla weak and absorb bytes, with
--      no Ot6ElemAddTbl row;
--   2. every species of every formation each fight deals (the event battle groups a script calls, read from
--      EventBattleGroup; map 149's pool) has an authored row and a key for each party that meets it there;
--   3. the cutscene bodies and the unreached markers are 0-shield rows (no gauge);
--   4. the lessons: on the raft each hand keys two of the three and TERRA's Fire all three; in the sparkle trap one
--      spirit to each hand, Fire to all, and poison heals them; the raiders take the troopers' keys; any weapon
--      breaks Siegfried.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SWORD, DAGGER, FIST, ARCANE, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x022] = { "Pterodon", 2, SWORD | SPEAR, FIRE, 0 },
  [0x038] = { "Nautiloid", 2, SPEAR | ARCANE, FIRE | BOLT, WATER },
  [0x039] = { "Exocite", 2, SWORD | ARCANE, FIRE | BOLT, WATER },
  [0x060] = { "Dark Side", 2, SWORD | DAGGER, FIRE | HOLY, POISON },
  [0x0B6] = { "Spectre", 2, FIST | ARCANE, FIRE | HOLY, POISON },
  [0x0CF] = { "Rinn", 1, SPEAR | ARCANE, FIRE | HOLY, POISON },
  [0x079] = { "Bounty Man", 2, DAGGER | KATANA, FIRE, 0 },
  [0x01C] = { "Fidor", 2, SWORD | DAGGER, FIRE, 0 },
  [0x0C2] = { "Sp.Forces", 3, SWORD | SPEAR, POISON, 0 },
  [0x00F] = { "Over-Mind", 2, SWORD | DAGGER, FIRE | HOLY, POISON },
  [0x131] = { "Siegfried", 1, DAGGER | KATANA | FIST, 0, 0 },
}
-- 0-shield rows: the cutscene bodies a called battle deals, and the markers for bodies no reachable formation holds
-- (tools/check_shield_rows.py proves the second list unreached; break-coverage-wob.md section 18 has the evidence)
local NO_GAUGE = {
  [0x179] = "the flashback soldier (battle 115)", [0x17A] = "the esper Kefka fights (battle 97)",
  [0x17B] = "the battle-event runner (battles 105, 121-123, 127)",
  [0x10F] = "Umaro $10F", [0x11A] = "Kefka $11A", [0x136] = "Colossus", [0x137] = "CzarDragon",
  [0x13B] = "B.Day Suit", [0x16E] = "$16E", [0x170] = "$170", [0x172] = "$172", [0x177] = "$177",
  [0x178] = "$178", [0x17F] = "$17F",
}
-- the parties (their hands: weapon classes, and the elements their spells, tools and weapons reach), from the
-- tracked checkpoints' gear and the route's battle logs (break-coverage-wob.md sections 13-17).  A hand is the
-- class of the weapon named for the member (the ROM's Ot6WeapClassTbl): TERRA's blade SWORD, EDGAR's pike and
-- AutoCrossbow SPEAR, BANON's Punisher (a rod) ARCANE, SABIN's fists and claws FIST, CYAN's katana and SHADOW's
-- ninja blade KATANA, LOCKE's knife DAGGER
local TERRA = { "TERRA", SWORD, FIRE }
local EDGAR = { "EDGAR", SPEAR, POISON }
local BANON = { "BANON", ARCANE, 0 }
local SABIN = { "SABIN", FIST, FIRE | HOLY }
local P = {
  raftUp = { "TERRA, EDGAR, SABIN, BANON", { TERRA, EDGAR, SABIN, BANON } },
  raft = { "TERRA, EDGAR, BANON", { TERRA, EDGAR, BANON } },
  squad1 = { "TERRA, EDGAR, CELES", { TERRA, EDGAR, { "CELES", SWORD, ICE } } },
  squad2 = { "CYAN, SABIN", { { "CYAN", KATANA, 0 }, SABIN } },
  squad3 = { "LOCKE, GAU", { { "LOCKE", DAGGER, 0 }, { "GAU", FIST, 0 } } },
  -- battle 30 is fought during the banquet, before the roster rewrite, by vector-crash-v1's party
  banquet = { "TERRA, LOCKE, EDGAR, SABIN", { { "TERRA", SWORD, FIRE | BOLT }, { "LOCKE", DAGGER, 0 },
    { "EDGAR", SWORD | SPEAR, ICE | POISON }, { "SABIN", FIST, FIRE | HOLY | POISON } } },
  train = { "SABIN, CYAN, SHADOW", { SABIN, { "CYAN", KATANA, 0 }, { "SHADOW", KATANA, 0 } } },
}
-- the fights: { label, "event", { event battle groups } | "map", map, its SubBattleGroup, parties, species dealt }
local FIGHTS = {
  { "the raft, upstream", "event", { 7, 8 }, { P.raftUp }, { 0x022, 0x038, 0x039 } },
  { "the raft, downstream", "event", { 8 }, { P.raft }, { 0x022, 0x038, 0x039 } },
  { "the sparkle trap", "event", { 38 }, { P.raft }, { 0x060, 0x0B6, 0x0CF } },
  { "the Narshe raiders", "event", { 22, 23 }, { P.squad1, P.squad2, P.squad3 }, { 0x079, 0x01C } },
  { "the banquet's troopers", "event", { 30 }, { P.banquet }, { 0x0C2 } },
  { "the train's Siegfried", "event", { 109 }, { P.train }, { 0x131 } },
  { "the train's vestibule car", "map", 149, 71, { P.train }, { 0x00F } },
}

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local problems = {}
    local function problem(fmt, ...)
      local msg = string.format(fmt, ...)
      problems[#problems + 1] = msg
      H.log("MISMATCH: " .. msg)
    end
    local function rom16(a) return H.readRomByte(a) | (H.readRomByte(a + 1) << 8) end
    local function readTable(a)
      local rows = {}
      while true do
        local sp = rom16(a)
        if sp == 0xFFFF then break end
        if rows[sp] == nil then rows[sp] = { H.readRomByte(a + 2), H.readRomByte(a + 3) } end
        a = a + 4
      end
      return rows
    end
    local shield = readTable(H.sym("Ot6ShieldTbl") & 0x3FFFFF)
    local elemAdd = readTable(H.sym("Ot6ElemAddTbl") & 0x3FFFFF)
    local prop = H.sym("MonsterProp") & 0x3FFFFF
    local function weak(sp) return H.readRomByte(prop + sp * 32 + 25) end
    local function absorb(sp) return H.readRomByte(prop + sp * 32 + 23) end
    local function classOf(sp) return shield[sp] and shield[sp][2] or 0 end
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm = H.sym("BattleMonsters") & 0x3FFFFF
    local function expand(word, out)
      for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do out[#out + 1] = (word & 0x1FF) + k end
    end
    local function poolForms(n)
      local out = {}
      for slot = 0, 3 do expand(rom16(rbg + n * 8 + slot * 2), out) end
      return out
    end
    local function eventForms(g)
      local out = {}
      expand(rom16(ebg + g * 4), out)
      expand(rom16(ebg + g * 4 + 2), out)
      return out
    end
    local function formSpecies(f)
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local out = {}
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then out[#out + 1] = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8) end
      end
      return out
    end

    -- 1. the designed rows
    local ids = {}
    for sp in pairs(WANT) do ids[#ids + 1] = sp end
    table.sort(ids)
    for _, sp in ipairs(ids) do
      local w = WANT[sp]
      local got = shield[sp]
      if got == nil then
        problem("$%03X %s has no Ot6ShieldTbl row (want %d, class $%02X)", sp, w[1], w[2], w[3])
      else
        if got[1] ~= w[2] then problem("$%03X %s shields %d, want %d", sp, w[1], got[1], w[2]) end
        if got[2] ~= w[3] then problem("$%03X %s class mask $%02X, want $%02X", sp, w[1], got[2], w[3]) end
      end
      if weak(sp) ~= w[4] then problem("$%03X %s weak byte $%02X, want vanilla $%02X", sp, w[1], weak(sp), w[4]) end
      if absorb(sp) ~= w[5] then
        problem("$%03X %s absorb byte $%02X, want vanilla $%02X", sp, w[1], absorb(sp), w[5])
      end
      if elemAdd[sp] ~= nil then problem("$%03X %s has an Ot6ElemAddTbl row; it should have none", sp, w[1]) end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. each fight's formations against the parties that meet it
    for _, fight in ipairs(FIGHTS) do
      local label, forms, parties, dealt = fight[1], {}, nil, fight[#fight]
      if fight[2] == "event" then
        for _, g in ipairs(fight[3]) do
          for _, f in ipairs(eventForms(g)) do forms[#forms + 1] = f end
        end
        parties = fight[4]
      else
        local group = H.readRomByte(sbg + fight[3])
        if group ~= fight[4] then problem("map %d (%s) deals pool group %d, want %d", fight[3], label, group, fight[4]) end
        forms = poolForms(group)
        parties = fight[5]
      end
      local seen, n = {}, 0
      for _, f in ipairs(forms) do
        for _, sp in ipairs(formSpecies(f)) do
          n = n + 1
          seen[sp] = true
          if shield[sp] == nil then
            problem("formation %d (%s): species $%03X has no authored row", f, label, sp)
          elseif shield[sp][1] > 0 then
            for _, party in ipairs(parties) do
              local cls, el = 0, 0
              for _, m in ipairs(party[2]) do cls, el = cls | m[2], el | m[3] end
              if (classOf(sp) & cls) == 0 and (weak(sp) & el) == 0 then
                problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s", f, label, sp,
                  classOf(sp), weak(sp), party[1])
              end
            end
          end
        end
      end
      for _, sp in ipairs(dealt) do
        if not seen[sp] then problem("%s no longer deals species $%03X", label, sp) end
      end
      H.log(string.format("checked %d formation-species pairs of %s", n, label))
    end

    -- 3. the bodies with no gauge
    local nNo = 0
    for sp, what in pairs(NO_GAUGE) do
      nNo = nNo + 1
      local got = shield[sp]
      if got == nil then problem("$%03X %s has no row (want the 0-shield marker)", sp, what)
      elseif got[1] ~= 0 or got[2] ~= 0 then
        problem("$%03X %s row is %d/$%02X, want 0/$00 (no gauge)", sp, what, got[1], got[2])
      end
    end
    H.log(string.format("checked %d 0-shield rows", nNo))

    -- 4. the lessons
    local raft = { 0x022, 0x038, 0x039 }
    for _, hand in ipairs({ { "TERRA's blade", SWORD }, { "EDGAR's pike", SPEAR }, { "BANON's rod", ARCANE } }) do
      local k = 0
      for _, sp in ipairs(raft) do if (classOf(sp) & hand[2]) ~= 0 then k = k + 1 end end
      if k ~= 2 then problem("the raft: %s keys %d of the three, want two", hand[1], k) end
    end
    for _, sp in ipairs(raft) do
      if (weak(sp) & FIRE) == 0 then problem("the raft: $%03X is not fire-weak; TERRA's Fire keys all three", sp) end
    end
    -- one spirit to each of the three hands: TERRA's blade, BANON's rod, EDGAR's pike
    local trap = { [0x060] = SWORD, [0x0B6] = ARCANE, [0x0CF] = SPEAR }
    local THREE = SWORD | SPEAR | ARCANE
    for sp, hand in pairs(trap) do
      if (classOf(sp) & THREE) ~= hand then
        problem("the trap: $%03X's keys among the three hands are $%02X, want the one $%02X", sp, classOf(sp) & THREE, hand)
      end
      if (weak(sp) & FIRE) == 0 or (absorb(sp) & POISON) == 0 then
        problem("the trap: $%03X should be fire-weak and drink poison", sp)
      end
    end
    for _, sp in ipairs({ 0x079, 0x01C }) do
      if classOf(sp) ~= classOf(0x065) then
        problem("$%03X: a raider should take the troopers' keys ($%02X), not $%02X", sp, classOf(0x065), classOf(sp))
      end
    end
    if classOf(0x131) ~= (SWORD | DAGGER | SPEAR | KATANA | FIST | ARCANE) then
      problem("Siegfried: every weapon hand should break him (class $%02X, want all six)", classOf(0x131))
    end
    H.log("the lessons: the raft splits its hands two-and-two, the trap one spirit to each hand, the raiders take "
      .. "the troopers' keys, any weapon breaks Siegfried")
    H.assertEq(#problems, 0, "WoB event-fight break row mismatches")
    H.log("WoB event-fight break rows verified against the built ROM")
  end),
})
