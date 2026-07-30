# Six physical break classes? — design exploration (2026-07-26)

**Scope:** should OT6 move from four physical break classes with typically one
weakness per species, to six with typically two? Survey and recommendation
only. No source was touched by this document; no assembly was written.

**Recommendation, up front: no. Keep four classes, and spend the effort on
authoring two-bit masks against the forced party instead.** The argument is in
§7; the strongest objection to it is stated and answered there too.

**Bit/space verdict, up front:** six classes **fit in the existing bytes with a
bit to spare and require no SRAM layout change and no re-mint**. This is not
the constraint. Neither, it turns out, are icons, the type column, Arrange
grouping, or menu-bank `$C3` work — all four are free (§5.1–§5.2). The
constraint is that in the parties FF6 actually fields, six classes make the
*authorable* palette smaller, not larger: on a normal four-character party the
current scheme is provably lockout-free and six is not (§4.2, §4.4).

> **Working-tree note.** While this survey was being written, another agent was
> landing the issue #19 fix (`ot6_hud.asm`: Number 128's three parts widened to
> `OT6_SLASH|OT6_PIERCE`) and the Vector shop change (`shop_prop.dat` shop 27
> gains Full Moon `$45` and Flail `$44`). Line numbers in `ot6_hud.asm` at or
> after 1548 are **+13** versus HEAD. All citations below are to the working
> tree as of writing, and the tallies in §5.4 are working-tree tallies.

> **CORRECTION — 2026-07-30. That "+13" note is now badly understated, and
> the `file:line` citations below have been re-pointed at today's tree.**
> Bank `$F0` grew a great deal between v0.6 and v0.9, so the drift is
> hundreds of lines, not thirteen. Ten citations in this survey resolved to
> unrelated code and were **fixed in place** (a stale line number is a
> typo, not a claim about the game): the null-break `bmi` tests, the shadow
> buffer's `.assert`, `Ot6ClassGlyphTbl`, `Ot6ElemPalTbl`, the class-message
> walk, `SortItemsByIcon` / `ItemIconTbl`, Number 024's shield row, the
> equip-mask read, and the pending-boost write. **The mechanism claims they
> support were each re-read and all of them still hold** — only the
> addresses had moved.
>
> **One count claim did NOT survive and is left standing as a record.**
> §5.4 says `Ot6ShieldTbl` "currently holds **62 records**". It now holds
> **74** (`ot6_hud.asm:1676-2155`, `$ffff` terminator at `:2155`, counted
> 2026-07-30). The mask/count breakdown §5.4 derives from that 62 has
> **not** been re-derived here, so treat every number in it as a v0.6-era
> tally, not a current one. Re-running it is a follow-up, not a typo fix —
> and the survey's *conclusion* (four classes stay, six does not fit) rests
> on the palette-bit argument in §4, not on this tally.

---

## 1. The bit and space budget, measured

Everything in this section was read out of the source, not assumed.

### 1.1 The class byte has three spare bits, and needs two

`ff6/src/battle/ot6_class.asm:10-17`:

```
OT6_SLASH   := $01
OT6_PIERCE  := $02
OT6_BLUDG   := $04
OT6_SPECIAL := $08
OT6_NULLBRK := $80              ; property, not a class
```

Bits `$10`, `$20`, `$40` are unallocated. Six classes occupy `$01`–`$20`,
leaving `$40` free and `$80` still reserved for null-break. The null-break
tests are `bmi` on bit 7 (`ot6_break.asm:942`, `ot6_icons.asm:570`, `:663`) and
stay correct unchanged. **Six fits; seven would fit; eight would collide.**

### 1.2 The battle RAM bytes are whole bytes, already

- `OT6_BP_CLASS := $3e9c` (`ot6_memory.inc:14`) — for monsters (`+8` and up,
  `$3ea4,y`) this byte is *only* the class-weak mask; nothing else shares it.
  For characters it is BP, a small integer, and the two halves never meet
  (every consumer is entity-gated — `ot6_break.asm:6-9` returns early for
  `y < $08`).
- `OT6_BOOST_REVEALED := $3e9d` (`ot6_memory.inc:15`) — same split: monster
  half = revealed-class mask (`$3ea5,y`, `ot6_hud.asm:363`), character half =
  pending boost 0–3 (`OT6_BOOST_REVEALED`, written at `ot6_kits.asm:991`).

Both monster halves are full 8-bit masks with four bits in use. Six classes
need no new storage.

### 1.3 The SRAM codex needs no migration

`ot6_memory.inc:23-35`:

```
OT6_CODEX_ROOT  := $316000      OT6_CODEX_STRIDE := $0400
OT6_CODEX       := ROOT+$0010   ; elements, 1 byte × 384 species
OT6_CODEX_CLASS := ROOT+$0190   ; classes,  1 byte × 384 species
OT6_CODEX_USED  := $0310
```

The class codex is **one byte per species**, and the `.assert` at `:33` proves
it ends exactly at `OT6_CODEX_USED`. Six revealed-class bits fit in that byte.
No offset moves, no page grows, `OT6_CODEX_USED` is unchanged, and therefore
**no magic bump and no deliberate re-mint** — the thing `m3-impl.md:44` had to
do when the class codex was first added (`'O6'`→`'O7'`) is not needed here.

### 1.4 The one format that is genuinely tight: the HUD strip

`ot6_hud.asm:293-300` (comment) and the cell-claim loops at `:314` / `:360`:
the under-monster line is **five cells** — cell 0 is the shield count, cells 1–4
are weakness slots **shared between elements and classes**, and a fifth
weakness truncates. The cap is enforced by `cmp #$09 / bcs @edone` in both
walks. The shadow buffer is 14 bytes per line × 6 lines
(`ot6_memory.inc:119-120`), so widening the row means moving the `$57c0+`
occupants.

How much does 2-of-6 cost here? Measured from `monster_prop.dat` `+25` across
all 384 species:

| vanilla element weaknesses | species |
|---|---|
| 0 | 80 |
| 1 | 177 |
| 2 | 113 |
| 3 | 10 |
| 4 | 1 |
| 8 | 3 |

- Today, a 1-class row truncates when elements ≥ 4: **4 species (1.0 %)**.
- Under 2-of-6, a 2-class row truncates when elements ≥ 3: **14 species (3.6 %)**.

That is a real regression but a small one, and I will not inflate it. The
sharper consequence is second-order: with 2 classes and 2 elements the strip is
*exactly full* for the 113 two-element species, so any future
`Ot6ElemAddTbl` row on those bodies would truncate. `balance-metrics.md:995-998`
calls the element-add table "the cheaper instrument" precisely because it
carries no `Ot6HpScale` exemption; 2-of-6 partially blunts the cheapest balance
lever we have.

### 1.5 ROM space

From `ff6/rom/ff6-en.map` (segment list):

| bank | contents | free |
|---|---|---|
| `$C1` | `btlgfx_code` `C10000-C1FF93`, `ot6_c1` `C1FFE8-C1FFF4` | **95 bytes** (0.14 %) |
| `$C2` | `battle_code` `C20000-C264B5`, next segment at `C26800` | **842 bytes** |
| `$C3` | `menu_code` `C30000-C3F22B`, bank ends `C3FFFF` | **3 540 bytes** |
| `$F0` | `ot6_code` `F00000-F01D46` (7 495 B) of a 1 MiB bank (`ff6/cfg/ff6-en.cfg:23`) | ~1 MiB |

The six-class change costs **zero bytes in `$C1`, `$C2` and `$C3`**: every edit
is either an in-place constant, a two-byte table extension in bank `$F0`, or a
data/JSON change. Specifically:

- the `cmp #$10` in the class walk → `cmp #$40` — same size.
- `Ot6ClassGlyphTbl` (`ot6_icons.asm:736`) 4 → 6 bytes — **+2 bytes, `$F0`**.
- `Ot6ElemPalTbl` (`ot6_icons.asm:479`) 12 → 14 bytes — **+2 bytes, `$F0`**.
- `Ot6WeapClassTbl` is 256 fixed bytes indexed by item id — reclassification is
  free.
- `Ot6ShieldTbl` records are 4 bytes with a one-byte mask (`ot6_break.asm:32`)
  — widening a mask is free.

**Budget verdict: fits in spare bits. No SRAM migration, no re-mint, ~4 bytes
of bank `$F0`.** Anything that argues against six classes has to argue on
design, not on space.

---

## 2. What the six would be — an actual proposal

Do not invent a taxonomy. FF6 already ships one, and this repo already used it:
before the M3 rename (`1bd9b69`, "the icon IS the class"), every weapon wore a
vanilla type icon. Decoded from `git show 1bd9b69^:ff6/src/text/item_name_en.json`,
the ten vanilla weapon types over 90 weapons are:

| vanilla type | icon | ids | n |
|---|---|---|---|
| dagger | `$d8` | `$00-$09`, `$25-$2a` | 16 |
| sword | `$d9` | `$0a-$1c` | 19 |
| spear | `$da` | `$1d-$24` | 8 |
| katana | `$db` | `$2b-$32` | 8 |
| staff/rod | `$dc` | `$33-$3c` | 10 |
| brush | `$dd` | `$3d-$40` | 4 |
| star | `$de` | `$41-$43` | 3 |
| "special" grab bag | `$df` | `$44-$4c` | 9 |
| card | `$e0` | `$4d-$52` | 6 |
| claw | `$e1` | `$53-$59` | 7 |

`docs/DESIGN.md:67-68` already names an eight from that vocabulary — "sword,
dagger, spear, katana, claw, rod, ranged (cards/dice/boomerangs/thrown),
brush". (That line is v1 vintage and stale against `weapon-classes.md` v2.1,
which is the current doc; flagged so a reader does not take the 8 as live.)

**The proposal is DESIGN.md's eight, minus the two classes v2.1 already
identified as one-wielder traps:** fold katana into blade (v2.1: "a one-wielder
class (katana) made Cyan feel mandatory"), and fold brush into ¤.

| # | class | contents | icon | type word |
|---|---|---|---|---|
| 1 | **blade** | swords `$0a-$1c`, katanas `$2b-$32` | `$d9` sword | `BLADE` |
| 2 | **dagger** | daggers `$00-$09`, ninja knives `$25-$2a`, stars `$41-$43` | `$d8` dagger | `DAGGER` |
| 3 | **spear** | spears `$1d-$24` | `$da` spear | `SPEAR` |
| 4 | **blunt** | rods `$34-$3c`, flail `$44`, morning star `$46`, bone club `$4a` | `$dc` staff | `BLUNT` |
| 5 | **claw** | claws `$53-$59`, empty hand `$ff` | `$e1` claw | `CLAW` |
| 6 | **¤ ranged** | returning arcs `$45/$47/$48/$4b/$4c`, hawk eye `$49`, cards/dice/darts `$4d-$52`, brushes `$3d-$40` | `$df` sparkle | `RANGED` |

This is the best six I can construct. It is guessable by anyone who has played
FF6, it keeps every icon vanilla, and it splits nothing arbitrarily. §3 is why
I still do not recommend it.

---

## 3. The character-coverage matrix

Equip permission is **per item**, not per character: a 16-bit character mask at
`item_prop_en.dat[item*30]+1..+2` (`ff6/src/menu/equip.asm:1599`,
`shop.asm:1415`, `battle_main.asm:13977`), stride 30 (`item.asm:1001-1012`),
bit→character per `CHAR_FLAG` (`ff6/include/const.inc:1416-1431`). Bit 15 is
Leo **and** the Merit Award override (`equip.asm:2300-2306`), so decoding it as
a fourteenth character reports phantom wielders on almost every weapon.

Decoded directly from `item_prop_en.dat` for ids `$00-$59`:

| character | dagger | sword | spear | ninja | katana | rod | brush | star | grab bag | claw |
|---|---|---|---|---|---|---|---|---|---|---|
| Terra | 4/10 | **all** | ✱ | — | — | — | — | — | 2 | — |
| Locke | **all** | 11/19 | ✱ | — | — | — | — | — | 6 | — |
| Cyan | — | 1 (Scimitar) | ✱ | — | **all** | — | — | — | — | — |
| Shadow | 7/10 | — | ✱ | **all** | — | — | — | — | — | — |
| Edgar | 4/10 | **all** | **all** | — | — | — | — | — | — | — |
| Sabin | — | — | ✱ | — | — | — | — | — | — | **all** |
| Celes | 4/10 | **all** | ✱ | — | — | — | — | — | 2 | — |
| Strago | 6/10 | — | ✱ | — | — | **all** | — | — | 2 | — |
| Relm | 6/10 | — | ✱ | — | — | **all** | **all** | — | 2 | — |
| Setzer | 4/10 | — | ✱ | — | — | — | — | — | 6 | — |
| Mog | 3/10 | — | **all** | — | — | — | — | — | — | — |
| Gau | — | — | ✱ | — | — | — | — | — | — | — |
| Umaro | — | — | — | — | — | — | — | — | Bone Club | — |

**✱ = Imp Halberd `$24` only** — mask `$dfff`, everyone but Umaro. It is a
1-power novelty that Imps the wearer. Treating it as spear access is a lie.

Everyone has **exactly one innate weapon slot**; the off-hand takes a weapon
only with a Genji Glove `$d1` (`equip.asm:2044-2078`, `battle_main.asm:2457-2461`).

### 3.1 Wielders per proposed class, WoB

| proposed class | free wielders in the WoB | verdict |
|---|---|---|
| **blade** | Terra, Celes, Edgar, Locke (11 swords), Cyan | healthy |
| **dagger** | Locke, Shadow, Terra, Celes, Strago, Relm, Setzer, Mog | healthy |
| **spear** | **Edgar, Mog** | marginal |
| **blunt** | Strago, Relm, Terra, Celes, Locke, Sabin (Blitz), Banon (Punisher, fixed) | healthy |
| **claw** | **Sabin. Only Sabin.** Umaro is WoR and can equip only the Bone Club (`$4a` mask `$2000`) | **fails** |
| **¤ ranged** | **Setzer, Relm** (+ Locke/Celes boomerangs, purchase-gated) | marginal |

The standing bar for adding a class — a class only one character can ever field
is worse than no class at all. **Claw fails that bar outright.** Any claw row is a
Sabin-mandatory row — which is verbatim the objection `weapon-classes.md:7-11`
recorded when v1's six classes were rejected ("a one-wielder class (katana)
made Cyan feel mandatory wherever katana locks appeared"). The proposal moves
that defect from Cyan to Sabin; it does not remove it.

And the reason claw fails is not fixable by regrouping. Merge claw into blade
and you have five classes — which is today's `SLASH` (`ot6_class.asm:140-146`:
claws are slashing precisely so Sabin buys into a shared class). Merge claw into
blunt and Sabin's weapon and his Blitzes agree, but you are back to today's
`BLUDG`. **The current four are not an arbitrary compression; each merge is
buying a shared wielder for a class that would otherwise have one.**

### 3.2 What a second class costs a character, in slots and gil

One weapon slot each, so **a character fields exactly one weapon class at a
time** and a second class costs either an inventory swap between fights or a
Genji Glove `$d1` (whose own mask is `$1fff` — everyone but Umaro). There is no
gil price on breadth for the characters who already span families: Locke's
sword line and Celes' dagger line are the same shop trip as their default. The
gil price is real only where a class has no native wielder in the party, and the
Vector band is the worked example — bludgeon there is a **purchase** (Full Moon
`$45` for Locke, Flail `$44` for Celes), sold in Narshe/Kohlingen/Jidoor/Tzen
but historically **not in Vector** (`break-band-vector.md:482-491`), which is
why the working tree is adding both to shop 27. (Gil prices not decoded here;
the constraint that bit was availability, not cost.)

The important consequence for the six-class question: **a second class costs a
slot, not a class count.** Widening the taxonomy does not give anybody a second
weapon; it only makes each character's single slot cover a smaller share of the
ring.

---

## 4. Does 2-of-6 fix the lockout, or move it?

### 4.1 The frame

A hard fight is not a failure. A fight where the correct answer is expensive,
or punishes a careless loadout, is a design outcome we want. The only condition
that counts as a defect is the one in issue #19: **no available action can chip
a shield at all**, so the break pillar is inert for the duration.

So the metric is not "how comfortable"; it is "is there a reachable axis".

### 4.2 The structural arithmetic

Let *N* = classes in the scheme, *W* = weaknesses authored per species, *K* =
distinct classes the party can field. If weaknesses were placed without regard
to the party (which is what "structural odds" means — authoring can drive any
of these to zero), the chance of no overlap is hypergeometric:

    P(lockout) = C(N-K, W) / C(N, W)

| party classes *K* | today **1-of-4** | proposed **2-of-6** | alternative **2-of-4** |
|---|---|---|---|
| 1 | C(3,1)/C(4,1) = **75.0 %** | C(5,2)/C(6,2) = 10/15 = **66.7 %** | C(3,2)/C(4,2) = 3/6 = **50.0 %** |
| 2 | 2/4 = **50.0 %** | C(4,2)/15 = 6/15 = **40.0 %** | C(2,2)/6 = 1/6 = **16.7 %** |
| 3 | 1/4 = **25.0 %** | C(3,2)/15 = 3/15 = **20.0 %** | 0 = **0 %** |
| 4 | **0 %** | C(2,2)/15 = 1/15 = **6.7 %** | **0 %** |

Three things fall out of that table.

1. **The dominant case decides it. A freely chosen four-character party is
   structurally lockout-proof under four classes (0 %) and is not under six
   (6.7 %).** Four classes reach zero at *K*=3; six do not reach zero until
   *K*=5, and with one weapon slot each (`equip.asm:2044-2078`) a four-character
   party fields *K*=4 unless a member carries a second class through a skill.
   Most of FF6 is a three- or four-character party drawn from the roster, so
   this row is the one that matters most, and it points the wrong way for six.
2. **2-of-6 reduces lockouts but never eliminates them.** The honest numbers:
   75 % → 66.7 % at *K*=1, 50 % → 40 % at *K*=2, 25 % → 20 % at *K*=3, and
   0 % → **6.7 %** at *K*=4. On the party shape the game presents most often,
   six classes make lockout *more* likely, not less.
3. **Widening *W* inside four classes beats widening *N* to six at every party
   size.** 2-of-4 is 16.7 % at *K*=2 where 2-of-6 is 40 %, and 0 % from *K*=3
   up.

### 4.3 Party sizes: the evidence, and a documentation conflict

The party sizes in the Vector band are contested between two docs in this repo,
and the answer changes which row of §4.2 applies. I decoded the event script
rather than pick a side. `party_chars` is event command `$3c`, four character
slots with **`$ff` = empty slot** — the disassembly's own comment at
`ff6/src/field/event.asm:590-594`, and `EventCmd_3c` (`:596-622`) branches out
of the fill loop on the first `$ff`, leaving the remaining slots pointing at the
null object `$07d9`.

The chain through the band, from `ff6/src/event/event_main.asm`:

| line | command | resulting party |
|---|---|---|
| 95796 | `party_chars LOCKE, CELES` | **2** — Ifrit, Shiva, Number 024 |
| 96154 | `char_party CELES, 0` | Celes removed |
| 96156 | `party_chars LOCKE` | **1** — the minecart and Number 128 |
| 96157-96158 | `switch $02F6=0` / `remove_equip CELES` | Celes' gear returns to inventory |
| 96739 | `party_chars LOCKE` | **1**, reasserted |
| 96982 | `char_party SETZER, 1` | **2** — Locke + Setzer, the Cranes |

There is no other `party_chars` or `char_party` anywhere between 96158 and
96982 (grepped over the whole range).

> **This derivation does not settle the question, and its conclusion is not
> adopted here.** `event_main.asm` is a dump of separately-addressed event
> scripts, not a linear program — fourteen distinct `_cc....:` script labels sit
> between `:96156` and the `cutscene TRAIN` at `:96580`. Proximity in the dump
> establishes nothing about execution order, so a chain assembled from adjacent
> `party_chars` lines cannot show which one is live at a given fight. The opcode
> reading above is sound; the ordering inference on top of it is not.
>
> **Working assumption: four characters in the Facility, three after Celes is
> lost partway through** — the owner's account from play, and what
> `bosses-wob.md` §13–§16 has said all along. Party composition is runtime state
> and is to be **measured** at the fixture (read the live party at each
> set-piece doorstep) rather than derived from source. Until that measurement
> exists, treat the sizes below as provisional and prefer the larger shape.

That makes `wob-route.md:78-85` and `break-band-vector.md` rev 2 correct, and
`bosses-wob.md` §13–§16 ("Party: Locke, Celes + two", "same four, on rails",
"the factory four") wrong. That is not a new discovery — **issue #19's fourth
acceptance criterion is literally "`bosses-wob.md` sections 15 and 16 no longer
claim a four-character party."** I am recording it here because the correction
was proposed in the other direction, and CONTRIBUTING's rule is to read the
source rather than propagate a recalled mechanism.

**This does not change the recommendation, and it is worth saying why.** The
argument for keeping four classes is *stronger* on large parties than on small
ones: at *K*=4 the current scheme is provably lockout-free and six is not. So
whichever way the party-size question is finally settled, the conclusion holds
— it is only the emphasis that moves. The rest of this section therefore
evaluates both shapes.

### 4.4 The free three- and four-character party — the normal case

For most of the World of Balance the party is three or four, chosen from the
available roster. From §3's matrix, a free four can trivially field all four
current classes — e.g. Cyan (slash), Edgar (pierce), Sabin (bludgeon via Blitz),
Setzer (¤) — so *K*=4 and the class axis cannot lock out at all. Under the §2
six, that same four fields blade, spear, claw/blunt, ¤ = at most 5 of 6 and
generically 4 of 6, leaving spear or dagger uncovered; a row authored on the two
classes the party happens to lack is a lockout that four classes could not have
produced.

The practical read: **on the game's normal party shape, four classes are not
merely adequate, they are the only one of the two schemes that is structurally
safe.** Six classes would import a failure mode into the majority case in order
to slightly soften one in the minority case.

### 4.5 The constrained stretches, and what actually changes there

These are the minority case, but they are where an author has to be careful.
Compositions decoded in §4.3 and (for the earlier scenarios) from
`bosses-wob.md:419-435` / `:499-503`. Below, "authorable" = classes with at
least one wielder present, i.e. the palette an author may legally draw from.
Note that a *hard* stretch is not a defect: the column to read is whether the
palette is empty, not whether it is comfortable.

| stretch | party | today: authorable / 4 | proposed: authorable / 6 |
|---|---|---|---|
| Vector A — Ifrit, Shiva, 024 | Locke + Celes | slash, pierce, bludg (purchase) = **3/4 = 75 %** | blade, dagger, blunt (purchase) = **3/6 = 50 %** |
| Vector B — minecart, Number 128 | **Locke solo, one slot** | slash, pierce, bludg (purchase) = **3/4 = 75 %** | blade, dagger, blunt (purchase) = **3/6 = 50 %** |
| Vector C — the Cranes | Locke + Setzer | all four = **4/4 = 100 %** | blade, dagger, blunt, ¤ = **4/6 = 67 %** |
| Doma courtyard | Cyan + Sabin | slash, bludg = **2/4 = 50 %** | blade, claw/blunt = **2/6 = 33 %** |
| Serpent Trench | Sabin, Cyan, Gau | slash, bludg = **2/4 = 50 %** | blade, claw, blunt = **3/6 = 50 %** |
| South Figaro | **Locke solo** | pierce (+ purchased bludg) = **2/4 = 50 %** | dagger (+ blunt) = **2/6 = 33 %** |

**Six classes shrink the authorable palette in every forced stretch but one.**
They do not add a reachable option to a small party; they subdivide the part of
the ring the party could never reach. `break-band-vector.md:544-550` already
reached the general form of this conclusion for four classes — *"a
two-character party cannot make a four-class ring interesting"* — and six
makes that strictly worse, because the two characters present now cover 33 %
of the ring instead of 50 %.

### 4.6 Number 128 specifically

The fight that prompted the question. Verified from `monster_prop.dat`:

```
$10b Number 128 body   weak=$00 (none)   absorb=$02 (ice)
$13f right blade       weak=$00 (none)   absorb=$02 (ice)
$140 left blade        weak=$00 (none)   absorb=$02 (ice)
```

So all three parts are in the 80-species set with **no vanilla element
weakness at all**, and the obvious substitute is absorbed. The class row is the
entire break axis, exactly as issue #19 says.

Would six classes have prevented it? **No.** Under the proposal, the row as
authored would have been body = SPEAR, blades = BLADE, and Locke — who fields
DAGGER or BLADE, one at a time — is locked out of the body just as hard. The
row was wrong because it was authored for a four-character party that
`wob-route.md:78-85` proves does not exist, not because there were four classes
to choose from. Widening it to `SLASH|PIERCE` — which is what the working tree
now does, matching Number 024 in the row directly above at `ot6_hud.asm:1973` —
costs one byte and fixes it completely.

Worth flagging while here: `bosses-wob.md:613-617` states Number 128's body is
"bolt, water + piercing" and `wob-route.md:258-259` repeats it. **The vanilla bytes
say otherwise** (`weak = $00`), and there is no `Ot6ElemAddTbl` row for `$10b`.
The doc's stated design intent is therefore unimplemented — an element ADD of
bolt|water on the three parts would make the documentation true and give solo
Locke a second axis if he learned Bolt from Ramuh (`break-band-vector.md:501-505`
flags that Bolt is learned magic, not guaranteed gear). That is a cheaper and
more on-brand fix than any class-count change.

### 4.7 A live defect the same method turned up

Applying this discipline to the Serpent Trench found an authoring error in the
*current* scheme, which is itself evidence about where the real risk lives.

*(Finding kept in its original tense; **the byte was fixed in v0.6 by issue
#23** — Aspik is `2 · bludg` now, and the trench trio is Anguiform slash /
Actaneon bludg / Aspik bludg, two keys across three creatures. What follows is
why, and is the part worth remembering.)*

`bosses-wob.md` authored Aspik `$0059` as `2 · pierce`, "punctured by
Gau's fanged strike". But **Gau cannot equip Hardened** — `$28` has mask
`$8008` = Shadow (+ Merit Award) only. Gau's entire legal weapon list is the
Imp Halberd. With no weapon his Fight reads `$ff` = bare fist = **bludgeon**
(`ot6_class.asm:163`), which `m3-impl.md:157-158` already flags as a known wart
("plain Gau punches bludgeon (`$ff` fists), not the kit's 'fangs = piercing'").

So the trench trio's real ring is **{slash (Cyan katana, SwdTech; Sabin claws),
bludgeon (Sabin Blitz, Gau fists)}** — and Aspik's pierce row is dead for the
only party that ever fights it. It is not a lockout: Aspik is fire-weak in
vanilla and Sabin's Fire Dance is reachable at L15. But it is a class row that
teaches nothing to its own audience, and it survived because the wielder claim
was recalled rather than decoded. **Six classes would not have caught it. A
decode would.**

---

## 5. The cost, honestly

### 5.1 Icons — the three-way split

Verified, not inferred. `git show` of `1bd9b69` shows exactly **one** font tile
was ever redrawn (`ff6/src/gfx/small_font_en.2bpp`, tile `$e0` only — I diffed
the 4 096-byte file against its parent, byte by byte). Everything else in the
icon block is untouched vanilla art that vanilla itself rendered.

| status | codes | notes |
|---|---|---|
| **(a) exists and already wired as a class glyph** | `$d9` sword, `$da` spear, `$dc` staff, `$df` sparkle | `Ot6ClassGlyphTbl`, `ot6_icons.asm:736`. Its header comment says these ship in the vanilla small font and need no upload — true of the whole block. |
| **(b) exists in the shipping font, needs only a pointer + a type word** | `$d8` dagger, `$db` katana, `$dd` brush, `$de` star, `$e1` claw | Vanilla used all five (dagger 16 weapons, katana 8, brush 4, star 3, claw 7). Five available; six classes need two. |
| **(c) genuinely needs drawing** | **none** | For any six drawn from vanilla's ten. |

`$e0` is the one that is spoken for: M3 redrew it as a dash for classless
weapons (Heal Rod, `item_name_en.json:$33`, type word `-----`).

**So the coordinator is right and my brief's framing was wrong: new icon art
costs nothing.** This changes the cost weighting substantially — see §7's
answer to the objection.

### 5.2 The type column and Arrange — also free

- The type word is derived arithmetically from the icon byte:
  `LoadItemTypeName` (`ff6/src/menu/item.asm:489-518`) does `sbc #$d8` and
  indexes `ItemTypeName` by `(icon-$d8)*7`. `item_type_name_en.json` has 16
  fixed-width 7-byte slots. All six proposed words fit: `BLADE`, `DAGGER`,
  `SPEAR`, `BLUNT`, `CLAW`, `RANGED`. **Zero bytes, JSON only.**
- **Inventory Arrange is already class-grouped for free and needs no change at
  all.** `SortItemsByIcon` (`ff6/src/menu/field_menu.asm:2227`) walks
  `ItemIconTbl` (`:2241`) = `$ff, $d8..$e7` — the *entire* icon block, 17
  entries. Adding classes on `$d8`/`$e1` groups correctly with no edit.
- **No menu-bank `$C3` work at all.** Grepping `ff6/src/menu/*.asm` finds no
  class-bit logic anywhere; the only OT6 hooks there are codex save/load and the
  Bushido loadout menu. The expensive kind of work this project has repeatedly
  flagged is **not** on this change's critical path.

### 5.3 Messages

`ot6_break.asm:961-967` sets `$3401 = $45` and walks the class bit with
`lsr`/`inc`. `attack_msg_en.json` slots `$45-$48` hold the four class messages
and **`$49` and `$4a` are empty** — exactly two free, contiguous, immediately
after. Two new strings in a text bank; the walk needs no code change.

### 5.4 Re-authoring: this is the real bill

`Ot6ShieldTbl` (`ot6_hud.asm:1273-1608`, 4-byte records) currently holds **62
records**:

*(**2026-07-30:** stale on both counts — the table is now at
`ot6_hud.asm:1676-2155` and holds **74** records. The tally below is a
v0.6-era snapshot and has not been re-derived; see the correction at the top
of this file.)*

| mask | count |
|---|---|
| `$00` (shields only, no class) | 13 |
| exactly 1 bit | 27 — PIERCE 17, SLASH 5, BLUDG 5, **SPECIAL 0** |
| exactly 2 bits | 21 — `SLASH\|PIERCE` ×13, `SLASH\|BLUDG` ×4, `PIERCE\|BLUDG` ×2 |
| 4 bits | 1 (Speck `$0146`, "any weapon breaks it") |

Plus the generated floor: `ot6_break_floor.inc`, **384 single-byte entries**,
one per species, distribution **SLASH 285 / PIERCE 75 / BLUDG 24 / SPECIAL 0**
(`gen_break_floor.py:26-28` defines only three class constants; `$ff` never
emits SPECIAL). `break_floor_review.txt` records 265 of those as *defaulted*,
i.e. unmatched by the name classifier — issue #11's headline number.

A class-taxonomy change means: re-deriving 89 weapon bytes in
`Ot6WeapClassTbl`, re-checking 12 ability bytes in `Ot6SkillClassTbl`,
re-authoring 49 class-bearing rows against their forced parties, rewriting
`gen_break_floor.py`'s rule table and regenerating 384 floor bytes, and
updating the per-id expectations in `battle_class.lua:94-95,241-242` and
`battle_breaktbl.lua:82-101`. That is a milestone of careful work, and it lands
on top of issue #11, which is *already* an unfinished band-by-band re-authoring
of the same data.

### 5.5 One number that should stop the conversation

**`OT6_SPECIAL` appears in exactly one authored row out of 62** — Speck's
"any physical class" catch-all — **and zero times in the 384-entry generated
floor.** Eleven months into authoring, OT6 cannot find work for the fourth
class it already has. Its own design doc lists "¤-weak density" as open
question #1 (`weapon-classes.md:145-148`) and `break-band-vector.md:538-540`
concludes ¤ "has exactly one legitimate home" in the entire Vector band.

Adding a fifth and sixth class to a system that has not populated its fourth is
solving the wrong problem.

---

## 6. The cheaper alternatives, steelmanned

### A. Keep four classes, author two weaknesses per species

**This is not a workaround; it is what the codebase already does.** 21 of 62
rows carry two bits today, including the entire imperial-soldier pass
(`bosses-wob.md:419-435`): `Soldier 2·slash|pierce`, `Grunt 2·slash|bludg`,
`Cadet 3·slash|bludg`, `Trooper`, `Rider`, `HeavyArmor`. That pass exists
because the fixed-party audit found the imperial line "unbreakable by the exact
party the game hands you", and the fix was **"a weapon class, chosen per the
forced party"** — a two-bit mask sized to whichever pair of heroes is standing
there.

Cost: zero code, zero UI, zero SRAM, zero new tests. Benefit, from §4.2:
**16.7 % structural lockout at *K*=2 against 2-of-6's 40 %, and 0 % at *K*=3
where six never reaches zero at all.**

The one honest cost: a second bit is a second `?` on the HUD, and
`balance-metrics.md:879-882` is right that a weakness the party hits by accident
is not a decision. But `break-band-vector.md:544-550` has already established
that on a two-character band *no* class row is deliberate, because the two
characters' default swings cover the reachable half of the ring. Where the
class ring is degenerate the second bit costs nothing in decision-quality,
because there was no decision to lose.

**And on a full party the second bit is not even needed for coverage** — a free
four already fields all four classes, so a one-bit row is safe there and stays
the better teaching tool. That is the shape to author to: **one bit where the
party is free, two where the story narrows it.** Four classes support that
gradient natively; six would need two bits everywhere just to hold the line,
which is the same authoring burden with a worse floor.

### B. Widen only the rows the story narrows the party for

Alternative A, targeted. It is literally issue #19's proposed fix, and it is
already applied in the working tree. The forced-party list is short and
enumerated (`wob-route.md:225-233`, `:78-85`): Locke solo ×2, Cyan solo, Cyan +
Sabin, Sabin + Cyan + Gau, Locke + Celes, Locke + Setzer, Terra + Locke +
Strago. Auditing 49 rows against seven forced parties is a day's work with a
decode, not a milestone.

**What it also wants, and this is the part worth funding:** a fixture assertion,
per issue #19's third acceptance criterion, that at each forced doorstep the
party's actual equipped weapons resolve to a class present in the row.
`break-band-vector.md:826-865` already sketches the shape.
`bal_party.lua:242-248` already reads `Ot6ShieldTbl` symbolically. The Aspik
finding in §4.5 is precisely the class of bug such a check catches, and no class
count catches it.

### C. Lean on the element axis

Eight axes, icons already drawn and uploaded (`Ot6ElemGlyphTbl`,
`ot6_icons.asm:126-133`), messages already authored (`$15-$1c`), and an
authoring instrument — `Ot6ElemAddTbl` — that `balance-metrics.md` explicitly
calls *cheaper* than a shield row because it carries no `Ot6HpScale` exemption.
Measurement #8 chose it over the class axis for the whole Figaro→Kolts stretch,
for the reason that decides it: **elements are deliberate where classes are
not.** Terra's Fire costs a menu dive; the A button is free.

Limits, stated: 80 of 384 species have no vanilla element bit, and an add is
illegal where the species absorbs the obvious answer (Number 128 absorbs ice).
And the axis needs a caster: solo Locke's element access is whatever he learned
from Ramuh, which is a route-dependent maybe.

**Verdict on the three:** A and B get essentially all of the benefit for none of
the cost, and C is the better instrument wherever a caster is present. A + B +
C is a strictly better package than six classes, and it is deliverable inside
issue #11's existing scope.

---

## 7. Recommendation

**Keep four physical classes. Author two-bit masks wherever the story
constrains the party, and fund a fixture that proves each forced party holds a
key to the row it will meet.**

The argument in one line: six classes are cheap to build and expensive to
*use*, because they shrink the palette an author may legally draw from — and
they do it in **both** party shapes at once.

- **On the normal three-or-four-character party, which is most of the game,
  four classes are provably lockout-free (*K*=4 → 0 %) and six are not
  (6.7 %).** Six classes cannot reach zero below *K*=5, and every character has
  one weapon slot (`equip.asm:2044-2078`). This is the decisive row: the change
  would import a new failure mode into the majority case.
- **On the constrained stretches, six shrink the authorable palette further
  still** — 75 % → 50 % in the Vector band, 50 % → 33 % at Doma and South
  Figaro.
- **And the alternative that costs nothing — two bits of four — beats six on
  the very metric that prompted the question:** 16.7 % against 40 % at a
  two-class party, and 0 % from *K*=3 up.

And the failure that prompted the question was not a scheme failure. Number 128
was authored PIERCE/SLASH/SLASH for "the factory four" that `bosses-wob.md` §15
still claims and the event scripts disprove. One byte per part fixes it under
four classes; under six it would have been authored just as wrong, and cost
more to fix.

### The strongest objection to this recommendation

*"Icons and menu work turned out to be free, the bits fit, and the SRAM does
not move. You are recommending against the richer system on the strength of a
combinatorial argument, when the real reason six classes are better is
**identity** — Octopath's six weapon types make every character's line feel
distinct, and OT6's compression makes Cyan's katana, Terra's sword and Edgar's
Chainsaw literally the same probe. That is the north star, and you are trading
it away for authoring convenience."*

That is the objection, and it is a good one. The answer is in three parts.

1. **The identity is already delivered on the element axis, which is eight
   wide and untouched** (`weapon-classes.md:41`). Octopath's twelve axes are
   six weapons + six elements; OT6's twelve are four classes + eight elements
   (`ot6_class.asm:4-5` says so explicitly). The count matches; only the
   *split* differs, and FF6's split is the right one because FF6 has eight
   native elements and a roster where six of the ten weapon families have one
   or two wielders.

2. **Octopath can afford six weapon types because every one of its eight
   characters is guaranteed available and each can hold two weapon types.**
   OT6's WoB hands you Locke alone with one slot, then Locke + Celes, then Cyan
   alone, then Cyan + Sabin. `equip.asm:2044-2078` proves there is no second
   weapon slot without a Genji Glove. Six types over a one-slot solo character
   is not Octopath's design; it is Octopath's design with the enabling
   condition removed.

3. **The specific identity gain is smaller than it looks, and one of the six
   is a trap.** Claw has exactly one wielder in the entire game
   (`item_prop_en.dat` `$53-$59` mask `$8020` = Sabin + Merit Award), and
   `weapon-classes.md:7-11` already rejected six classes once for precisely
   this defect. Meanwhile `Ot6WeapClassTbl` already gives Sabin a second class
   through claws and Edgar a second through the Chain Saw
   (`weapon-classes.md:26-27`; `ot6_class.asm:154`), and `Ot6SkillClassTbl` gives every kit a
   line outside its weapon. The identity mechanism exists; it is skills and
   crossover weapons, not class count.

If the goal is that weapons *feel* more distinct, the cheap version of that is
available too and it is already in the doc: `weapon-classes.md:55-58` says a
desire for more visual distinction "is a reason to consider another weapon
class, not to add a second icon set with no mechanical meaning." Given §5.1,
the inverse is now also true — the icons are free, so if a seventh probe axis
is ever wanted, the cheapest one is **not a fifth and sixth class but a
null-break-style property**, or a ninth element, both of which cost nothing in
party coverage.

### If the owner overrules this

Then the order of operations that minimises risk:

1. Do issue #11's band-by-band re-authoring **first**, under four classes. It
   is the same work either way, and it is the only way to learn whether the ¤
   class can be populated at all — which is the live evidence for or against a
   fifth and sixth.
2. Adopt the §2 six exactly (vanilla types, vanilla icons), so no art is drawn
   and the Arrange/type-column path stays untouched.
3. Fold claw into blade on day one and ship **five**, adding the sixth only if
   a second claw wielder ever appears.
4. Land the forced-party fixture from §6B *before* the taxonomy change, so the
   re-authoring pass has a net under it.
