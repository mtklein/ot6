.ifndef MENU_TEXT_INC
MENU_TEXT_INC = 1

; ------------------------------------------------------------------------------

; misc. individual text characters
.define ZERO_CHAR                       z"0"
.define COLON_CHAR                      z":"
.define GAUGE_EMPTY_CHAR                z"{gauge_empty}"
.define GAUGE_FULL_CHAR                 z"{gauge_full}"
.define GAUGE_LEFT_CHAR                 z"{gauge_left}"
.define GAUGE_RIGHT_CHAR                z"{gauge_right}"

; ------------------------------------------------------------------------------

; field menu text strings
.define MAIN_MENU_WOUNDED               {z"Wounded "}

.define CHAR_BLOCK_1_LEVEL              BG1A, {10, 5}, {"LV"}
.define CHAR_BLOCK_1_HP                 BG1A, {10, 6}, {"HP"}
.define CHAR_BLOCK_1_MP                 BG1A, {10, 7}, {"MP"}
.define CHAR_BLOCK_1_HP_SLASH           BG1A, {17, 6}, {"/"}
.define CHAR_BLOCK_1_MP_SLASH           BG1A, {17, 7}, {"/"}

.define CHAR_BLOCK_2_LEVEL              BG1A, {10, 11}, {"LV"}
.define CHAR_BLOCK_2_HP                 BG1A, {10, 12}, {"HP"}
.define CHAR_BLOCK_2_MP                 BG1A, {10, 13}, {"MP"}
.define CHAR_BLOCK_2_HP_SLASH           BG1A, {17, 12}, {"/"}
.define CHAR_BLOCK_2_MP_SLASH           BG1A, {17, 13}, {"/"}

.define CHAR_BLOCK_3_LEVEL              BG1A, {10, 17}, {"LV"}
.define CHAR_BLOCK_3_HP                 BG1A, {10, 18}, {"HP"}
.define CHAR_BLOCK_3_MP                 BG1A, {10, 19}, {"MP"}
.define CHAR_BLOCK_3_HP_SLASH           BG1A, {17, 18}, {"/"}
.define CHAR_BLOCK_3_MP_SLASH           BG1A, {17, 19}, {"/"}

.define CHAR_BLOCK_4_LEVEL              BG1A, {10, 23}, {"LV"}
.define CHAR_BLOCK_4_HP                 BG1A, {10, 24}, {"HP"}
.define CHAR_BLOCK_4_MP                 BG1A, {10, 25}, {"MP"}
.define CHAR_BLOCK_4_HP_SLASH           BG1A, {17, 24}, {"/"}
.define CHAR_BLOCK_4_MP_SLASH           BG1A, {17, 25}, {"/"}

.define MAIN_MENU_ITEM                  BG3A, {24, 3}, {"Item"}
.define MAIN_MENU_SKILLS                BG3A, {24, 5}, {"Skills"}
.define MAIN_MENU_EQUIP                 BG3A, {24, 7}, {"Equip"}
.define MAIN_MENU_RELIC                 BG3A, {24, 9}, {"Relic"}
.define MAIN_MENU_STATUS                BG3A, {24, 11}, {"Status"}
.define MAIN_MENU_CONFIG                BG3A, {24, 13}, {"Config"}
.define MAIN_MENU_SAVE                  BG3A, {24, 15}, {"Save"}
.define MAIN_MENU_TIME                  BG3A, {25, 17}, {"Time"}
.define MAIN_MENU_COLON                 BG3A, {27, 18}, {":"}
.define MAIN_MENU_STEPS                 BG3A, {23, 21}, {"Steps"}
.define MAIN_MENU_GIL                   BG3A, {23, 24}, {"Gp"}

.define GAME_LOAD_YES                   BG3A, {26, 9}, {"Yes"}
.define GAME_LOAD_NO                    BG3A, {26, 11}, {"No"}
.define GAME_LOAD_MSG_1                 BG3A, {23, 3}, {"This"}
.define GAME_LOAD_MSG_2                 BG3A, {23, 5}, {"data?"}

.define GAME_SAVE_MSG_1                 BG3A, {23, 3}, {"Erasing"}
.define GAME_SAVE_MSG_2                 BG3A, {23, 5}, {"data."}
.define GAME_SAVE_MSG_3                 BG3A, {23, 7}, {"Okay?"}

.define MAIN_MENU_ORDER                 BG3B, {26, 3}, {"Order"}

; ------------------------------------------------------------------------------

; colosseum menu text strings
.define COLOSSEUM_ITEM_TITLE            BG3A, {2, 3}, {"Colosseum"}
.define COLOSSEUM_ITEM_MSG              BG3A, {13, 3}, {"Select an Item"}

.define COLOSSEUM_CHAR_BLANK_NAME       BG3A, {22, 16}, {"      "}
.define COLOSSEUM_CHAR_MSG              BG3A, {6, 19}, {"Select the challenger"}
.define COLOSSEUM_UNKNOWN_PRIZE         BG3A, {2, 3}, {"?????????????"}

; ------------------------------------------------------------------------------

; skills menu strings
.define SKILLS_LIST_GENJU               BG3A, {2, 3}, {"Espers"}
.define SKILLS_LIST_MAGIC               BG3A, {2, 5}, {"Magic"}
.define SKILLS_LIST_BUSHIDO             BG3A, {2, 9}, {"SwdTech"}
.define SKILLS_LIST_BLITZ               BG3A, {2, 11}, {"Blitz"}
.define SKILLS_LIST_LORE                BG3A, {2, 13}, {"Lore"}
.define SKILLS_LIST_RAGE                BG3A, {2, 15}, {"Rage"}
.define SKILLS_LIST_DANCE               BG3A, {2, 17}, {"Dance"}
.define SKILLS_LIST_THIEF               BG3A, {2, 19}, {"Thief"}

.define SKILLS_MP_COST                  BG3B, {23, 5}, {"MP_    "}
.define SKILLS_LORE_TITLE               BG3B, {23, 5}, {"Lore"}
.define SKILLS_RAGE_TITLE               BG3B, {23, 5}, {"Rage"}
.define SKILLS_DANCE_TITLE              BG3B, {23, 5}, {"Dance"}
.define SKILLS_GENJU_TITLE              BG3B, {23, 5}, {"Espers"}
.define SKILLS_BLITZ_TITLE              BG3B, {23, 5}, {"Blitz"}
.define SKILLS_BUSHIDO_TITLE            BG3B, {23, 5}, {"SwdTech"}
.define SKILLS_THIEF_TITLE              BG3B, {23, 5}, {"Thief"}

.define SKILLS_CHAR_LEVEL               BG1B, {18, 7}, {"LV"}
.define SKILLS_CHAR_HP                  BG1B, {18, 9}, {"HP"}
.define SKILLS_CHAR_MP                  BG1B, {18, 11}, {"MP"}
.define SKILLS_CHAR_HP_SLASH            BG1B, {25, 9}, {"/"}
.define SKILLS_CHAR_MP_SLASH            BG1B, {25, 11}, {"/"}

.define GENJU_EQUIP_ERROR_MSG           {" has it!"}
.define GENJU_LEARN_PCT                 BG1B, {24, 15}, {"Skill"}
.define GENJU_LEARN_RATE                BG1B, {13, 15}, {"Learn.Rate"}
.define GENJU_AT_LEVEL_UP               {z"At level up..."}

; OT6 (#27): the esper detail page's while-worn stat-mod line.  The stat
; names are space-padded to exactly 7 characters (+ the terminator = the
; 8-byte stride Ot6GenjuStatNameTbl indexes by), matching the Vigor/Speed/
; Stamina/Mag.Pwr labels the status and equip screens use.
.define OT6_GENJU_WHILE_WORN            {z"While worn..."}
.define OT6_GENJU_STAT_VIGOR            {"Vigor  "}
.define OT6_GENJU_STAT_SPEED            {"Speed  "}
.define OT6_GENJU_STAT_STAMINA          {"Stamina"}
.define OT6_GENJU_STAT_MAGPWR           {"Mag.Pwr"}

; OT6 (#8 Layer B / #39): the Bushido loadout configurator's labels.  These
; MUST come through this file's encode pipeline: a bare string literal in
; field_menu.asm assembles under the ending-credits .charmap that
; ending_anim.asm installs earlier in menu_main.asm's include order (and gets
; no $00 terminator), which is exactly issue #39's garbled SwdTech page.
; #43: rows must be odd and <= 15: the EN window shows a tilemap row pair in
; twelve scanlines (odd eight, even four) and stops after row 15.  These labels
; shipped on rows 4/6/8 and the LEARNED caption on 13 with its grid running to
; 21, so every slot rendered as a four-scanline sliver and most of the pool was
; off the bottom.  See Ot6LoadoutDrawSlots' cadence note in field_menu.asm.
;
; The cursor gutter (#43, third round).  Columns 1-2 belong to the cursor
; sprite, not to text.  The menu cursor is 16x16 and `cursor_pos {x,y}` is its
; top-left corner, measured on the shipped ROM's own magic list, whose
; `cursor_pos {8, 116}` puts the sprite at screen x 8..23, y 116..131
; (tools/tests/probe_menucols.lua).  So a cursor at x=8 covers tilemap columns
; 1 and 2, and the row it points at must begin at column 3.  Vanilla is
; consistent on the arithmetic, cursor_x = 8*col - 16:
;
;   magic   text cols 3 / 16  (skills.asm:831, :836)   cursors 8 / 112  (:125-126)
;   espers  text cols 3 / 17  (skills.asm:1733, :1737) cursors 8 / 120  (:249-250)
;   rage    text cols 5 / 19  (skills.asm:1544, :1548) cursors 24 / 136 (:292-293)
;   config  value col 14      (this file, :379)        cursor  96       (config.asm:50)
;
; These labels shipped at column 2 under a cursor at x=8, so the sprite drew
; over the leading glyph -- the "1" of "1x".  The page's left margin is column 3
; now and everything right of it moved with it; the cursor table did not move,
; because it was already vanilla's.
; #44: the title pays for the control hint.  L/R cycling the cursored tier is
; this page's only interaction and nothing on screen said so ("that part
; was not obvious", owner playtest, v0.7).  All eight of the window's text
; rows are already in use, so the hint needed space from somewhere, and the title
; was the cheapest source: "BUSHIDO LOADOUT" spanned columns 3-17 to say what
; the 1x/2x/3x tiers and the LEARNED pool below it already show.
;
; Shortening it to "SWDTECH" is also a naming fix that was owed anyway.  Every
; other player-facing string in the EN build calls this skill SwdTech
; (SKILLS_LIST_BUSHIDO :81, SKILLS_BUSHIDO_TITLE :93, ITEM_BUSHIDO :204)
; and "Bushido" is the internal/JP name.  This page was the one place the EN
; player was shown it, and it is the page reached by picking the row labelled
; "SwdTech", so the shorter title also matches the way in.
;
; The row is now three blue chrome words with one- and two-column gaps:
;   SWDTECH   3-9 | L/R SWAPS  11-19 | LEARNED  22-28
.define OT6_LOADOUT_TITLE               BG1A, {3, 1},  {"SWDTECH"}
; #44: the control hint.  Same wording, character for character, as the Rage
; page's OT6_RAGE_HINT below: both pages teach the same idiom and a player who
; learns it on one must not have to re-learn it on the other.  "SWAPS" is the
; owner's own verb for what L/R does (issue #44's title).  Drawn blue, with the
; title and the pool caption, so it reads as chrome and not as a slot's data.
.define OT6_LOADOUT_HINT                BG1A, {11, 1}, {"L/R SWAPS"}
; The caption rides the TITLE row (the Rage page's own resolution for its price
; line): the window holds eight text rows and the page needs nine -- title,
; three boost slots, the caption, and four rows of a two-column pool that must
; hold all eight techs.  Something had to double up, and the title row is the
; only row where a second blue chrome caption cannot be misread as data.
.define OT6_LOADOUT_POOL                BG1A, {22, 1}, {"LEARNED"}
; #38: every Bushido tech costs at least 1 BP, so the 0x row is retired and the
; page is three rows deep: 1x/2x/3x at tilemap rows 3/5/7 (#43).  These three
; are the cursored rows, so column 3 is not cosmetic here: it is the gutter rule
; above, and the overlap the owner saw was on this exact glyph.
;
; #56: the tech name now starts at column 5, immediately after these two cells,
; with no blank between.  #45's rescale made the price field five cells wide
; instead of four and this row had exactly one cell of slack in it; the full
; derivation of which of the row's three gaps could be the donor is over
; Ot6LoadoutDrawSlots (field_menu.asm).  Do not re-introduce a blank at column 5
; without taking the cell back from somewhere; the price field would go back
; to overwriting the mode block's separator.
.define OT6_LOADOUT_LBL1                BG1A, {3, 3},  {"1x"}
.define OT6_LOADOUT_LBL2                BG1A, {3, 5},  {"2x"}
.define OT6_LOADOUT_LBL3                BG1A, {3, 7},  {"3x"}
; The suffix both loadout pages and the Blitz page hang on a price.  Two digits
; ride in front of it (Ot6LoadoutDrawCost), so the field is five cells: a tens
; digit or a blank, a ones digit, then this.
.define OT6_LOADOUT_MP_SUFFIX           {" MP"}
; #49: the mode indicator and the revert control, in the one free block this
; page has: columns 23-29 of the three slot rows.  Row 3 carries the mode,
; row 5 the control that changes it; row 7 stays clear so the pair reads as a
; two-line group rather than a third column of data.
;
; Column 24, not 23, and the difference decides whether the row is legible.
; The slot's price field abuts column 23, so a block starting there renders the
; row as "7 MPMANUAL" (measured, first screenshot of that change).  Column 23
; is spent as the separator and the block runs 24-29, which is exactly as wide
; as the free run allows: column 30 is the window's own right border.
;
; #56 widened the price from four cells at 19-22 to five at 18-22, and took the
; extra cell off the other side of the row rather than out of column 23, so
; this block is where it was.
;
; Both halves are drawn by Ot6LoadoutDrawMode (field_menu.asm) after the slot
; loop rather than by DrawPosText at init, because Ot6LoadoutDrawCost's
; zero-cost arm blanks the whole five-cell price field on every redraw of the
; nomp build (which before #56 ran through column 23) and because that is
; what keeps the mode live (the slot loop is the only thing a redraw runs).
.define OT6_LOADOUT_MODE_HINT           BG1A, {24, 5}, {"Y=AUTO"}

; OT6 (#40): Gau's 8-slot rage loadout page.  Same encode-pipeline rule as the
; Bushido labels above: a bare literal in field_menu.asm picks up
; ending_anim.asm's credits charmap and carries no terminator (issue #39).
; Rows must be odd and <= 15: the EN window shows a tilemap row pair in twelve
; scanlines and stops after row 15 (Ot6RageDrawSlots' cadence note).  {2,20}
; put LEARNED off the bottom of the window entirely.
;
; Column 3 for the left margin, for the cursor-gutter reason spelled out over
; OT6_LOADOUT_TITLE above: this page's left slot column is cursored at x=8, so
; nothing of its rows may sit in columns 1-2.  The page's right slot column was
; already correct (col 16 under `cursor_pos {112, ...}` is vanilla's magic-list
; pair), which is why only the left half moves.  The title and the
; LEARNED caption follow it so the page has one left margin.
.define OT6_RAGE_TITLE                  BG1A, {3, 1},  {"RAGE LOADOUT"}
.define OT6_RAGE_EACH                   BG1A, {22, 1}, {"EACH"}
.define OT6_RAGE_LEARNED                BG1A, {3, 15}, {"LEARNED"}
; #44: the control hint, on row 3.  This page uses six of the window's eight
; text rows (1 title, 5/7/9/11 slots, 15 LEARNED); rows 3 and 13 are its
; deliberate breathing space, so unlike the Bushido page nothing had to be
; shortened to make room; row 3 sits directly under the title and directly
; above the first slot, which is where a first-time player looks next.
;
; Note for anyone re-deriving the budget: row 1 is not free on this page.  The
; flat trance price occupies it: a five-cell price field at columns 16-20
; (#56: five, not four, and one column further left so the EACH label below
; keeps its gap) and OT6_RAGE_EACH at 22-25 (Ot6RagePrice, field_menu.asm),
; so the title row's only spare runs are 15, 21 and 26-29.  None of them fits a
; legible hint.
;
; Identical wording to OT6_LOADOUT_HINT above, on purpose: the L/R idiom is the
; same on both loadout pages and is worth teaching once.
.define OT6_RAGE_HINT                   BG1A, {3, 3},  {"L/R SWAPS"}
; #44: what an unset slot says.  It is not "-default-": nothing defaults into
; an unset slot.  A blank row on this page has two causes and both mean
; the same thing: the slot is empty and contributes nothing to the battle
; list:
;   * AUTO (all eight bytes zero) with fewer than eight rages hunted:
;     Ot6RageNth returns carry clear past the end of the window
;     (ot6_kits.asm:1856-1858) and Ot6RageList's AUTO arm writes nothing for it;
;   * MANUAL with a $00 byte: Ot6RageSlot returns carry clear (:1820) and
;     Ot6RageList's @manual arm SKIPS the slot outright (:1993-2002).  Reachable
;     because Ot6RageSeed stops as soon as the window runs out (:2075), so
;     editing a loadout while fewer than eight are known leaves the tail unset.
; Calling either state "default" would be the #27/#32 class of error: the page
; would name something the battle menu does not contain.  The marker is
; MonsterName::ITEM_SIZE (10) cells wide so it overwrites a name completely,
; keeping the property the old $ff fill had: a revert wipes what was there.
.define OT6_RAGE_EMPTY                  {"- EMPTY - "}
; #49: the mode indicator and the revert control.  Row 13 was this page's one
; genuinely spare row (the page draws on 1/3/5/7/9/11/15), and the survey in
; issue #49 costed it at 27 free columns -- enough to carry both halves side by
; side.  Columns 3 and 16 are the page's own two slot columns, so the pair
; lines up with the grid above it instead of floating.
.define OT6_RAGE_MODE_HINT              BG1A, {16, 13}, {"Y=AUTO"}

; ------------------------------------------------------------------------------

; OT6 (#49): AUTO vs MANUAL, the state neither loadout page showed.
;
; An all-zero loadout means AUTO -- the game picks, and keeps re-picking as the
; character learns more (Ot6LoadoutAutoTech's moving window; Ot6RageNth's first
; eight in id order).  The first L/R edit freezes that window into the save
; bytes and the page is MANUAL from then on, permanently, until Y clears it.
; Nothing on either page said which of the two states the player was in, and
; nothing named Y -- the same discoverability gap #44 closed for L/R.
;
; The two words are the SAME WIDTH on purpose: six cells, "AUTO" space-padded.
; The field is redrawn in place on every redraw, so a MANUAL -> AUTO revert has
; to overwrite all six cells or the tail of "MANUAL" survives under "AUTO" --
; the same overwrite property OT6_RAGE_EMPTY is sized for.  Both pages draw
; from these two, so the vocabulary cannot drift between them.
.define OT6_MODE_AUTO                   {"AUTO  "}
.define OT6_MODE_MANUAL                 {"MANUAL"}

; ------------------------------------------------------------------------------

; OT6 (#46): the field Skills->Blitz page.
;
; The page shipped drawing vanilla's BUTTON COMBOS -- the left/right/down glyph
; strings the v0.4 blitz-as-menu change retired when Blitz became a list you
; pick from (Ot6BlitzListOpen, ot6_kits.asm).  It was teaching an input system
; the game no longer has, the #27/#39 class of surface.  It shows what a Blitz
; IS instead: name, break class, MP price.
;
; A NOT-YET-LEARNED row says so rather than going blank.  Vanilla drew ten pad
; cells for an unlearned blitz, which reads as a rendering fault (the owner's
; own reading of the Rage page's blank slots, issue #44).  Ten cells wide --
; exactly AttackName::ITEM_SIZE -- so it overwrites a name completely, the
; property OT6_RAGE_EMPTY is sized for.  "- LOCKED -" and not "- EMPTY -":
; nothing is empty here, the ladder is fixed and this tier is simply not
; reached yet, and the two words must not be used for two different facts.
.define OT6_BLITZ_LOCKED                {"- LOCKED -"}

; ------------------------------------------------------------------------------

; item menu text strings
.define ITEM_TITLE                      BG3A, {2, 3}, {"Item"}
.define ITEM_OPTION_USE                 BG3A, {10, 3}, {"USE"}
.define ITEM_OPTION_ARRANGE             BG3A, {15, 3}, {"ARRANGE"}
.define ITEM_OPTION_RARE                BG3A, {24, 3}, {"RARE"}

.define ITEM_UNKNOWN_ATTACK             BG3B, {29, 23}, {"???"}
.define ITEM_STRENGTH                   BG3B, {19, 15}, {"Vigor"}
.define ITEM_STAMINA                    BG3B, {19, 19}, {"Stamina"}
.define ITEM_MAG_PWR                    BG3B, {19, 21}, {"Mag.Pwr"}
.define ITEM_EVADE                      BG3B, {19, 27}, {"Evade %"}
.define ITEM_MAG_EVADE                  BG3B, {19, 31}, {"MBlock%"}
.define ITEM_SPEED                      BG3B, {19, 17}, {"Speed"}
.define ITEM_ATTACK_PWR                 BG3B, {19, 23}, {"Bat.Pwr"}
.define ITEM_DEFENSE                    BG3B, {19, 25}, {"Defense"}
.define ITEM_MAG_DEF                    BG3B, {19, 29}, {"Mag.Def"}
.define ITEM_ELEMENT_HALF               BG3A, {2, 13}, {"50% Dmg"}
.define ITEM_ELEMENT_ABSORB             BG3A, {16, 13}, {"Absorb HP"}
.define ITEM_ELEMENT_NULL               BG3A, {2, 17}, {"No Effect"}
.define ITEM_ELEMENT_WEAK               BG3A, {16, 17}, {"Weak pt"}
.define ITEM_ATTACK_ELEMENT             BG3A, {2, 13}, {"Attack"}

.define ITEM_STAT_SEP(yy)               BG3B, {27, yy}, {"{2dot}"}
.define ITEM_USAGE_MSG                  {" can be used by:"}

.define ITEM_BUSHIDO                    BG3B, {19, 7}, {"SwdTech"}
.define ITEM_RUNIC                      BG3B, {19, 9}, {"Runic"}
.define ITEM_2HAND                      BG3B, {19, 11}, {"2-hand"}
.define ITEM_OWNED                      BG3A, {2, 7}, {"Owned:"}
.define ITEM_BLANK_QTY                  BG3A, {27, 9}, {"   "}

.define EVADE_MODIFIER_0                {"  0"}
.define EVADE_MODIFIER_PLUS_10          {"+10"}
.define EVADE_MODIFIER_PLUS_20          {"+20"}
.define EVADE_MODIFIER_PLUS_30          {"+30"}
.define EVADE_MODIFIER_PLUS_40          {"+40"}
.define EVADE_MODIFIER_PLUS_50          {"+50"}
.define EVADE_MODIFIER_MINUS_10         {"-10"}
.define EVADE_MODIFIER_MINUS_20         {"-20"}
.define EVADE_MODIFIER_MINUS_30         {"-30"}
.define EVADE_MODIFIER_MINUS_40         {"-40"}
.define EVADE_MODIFIER_MINUS_50         {"-50"}

.define STAT_MODIFIER_0                 {z" 0"}
.define STAT_MODIFIER_PLUS_1            {z"+1"}
.define STAT_MODIFIER_PLUS_2            {z"+2"}
.define STAT_MODIFIER_PLUS_3            {z"+3"}
.define STAT_MODIFIER_PLUS_4            {z"+4"}
.define STAT_MODIFIER_PLUS_5            {z"+5"}
.define STAT_MODIFIER_PLUS_6            {z"+6"}
.define STAT_MODIFIER_PLUS_7            {z"+7"}
.define STAT_MODIFIER_MINUS_1           {z"-1"}
.define STAT_MODIFIER_MINUS_2           {z"-2"}
.define STAT_MODIFIER_MINUS_3           {z"-3"}
.define STAT_MODIFIER_MINUS_4           {z"-4"}
.define STAT_MODIFIER_MINUS_5           {z"-5"}
.define STAT_MODIFIER_MINUS_6           {z"-6"}
.define STAT_MODIFIER_MINUS_7           {z"-7"}

; ------------------------------------------------------------------------------

; equip/relic menu text strings
.define EQUIP_RHAND                     BG3A, {2, 7}, {"R-hand"}
.define EQUIP_LHAND                     BG3A, {2, 9}, {"L-hand"}
.define EQUIP_HEAD                      BG3A, {2, 11}, {"Head"}
.define EQUIP_BODY                      BG3A, {2, 13}, {"Body"}
.define EQUIP_RELIC1                    BG3A, {2, 11}, {"Relic"}
.define EQUIP_RELIC2                    BG3A, {2, 13}, {"Relic"}
.define EQUIP_BLANK_OPTIONS             BG3A, {2, 3}, {"                            "}
.define EQUIP_TITLE_EQUIP               BG3A, {24, 3}, {"EQUIP"}
.define EQUIP_TITLE_REMOVE              BG3A, {24, 3}, {"REMOVE"}
.define EQUIP_OPTION_EQUIP              BG3A, {2, 3}, {"EQUIP"}
.define EQUIP_OPTION_OPTIMUM            BG3A, {9, 3}, {"OPTIMUM"}
.define EQUIP_OPTION_REMOVE             BG3A, {18, 3}, {"RMOVE"}
.define EQUIP_OPTION_EMPTY              BG3A, {25, 3}, {"EMPTY"}
.define RELIC_OPTION_EQUIP              BG3A, {4, 3}, {"EQUIP"}
.define RELIC_OPTION_REMOVE             BG3A, {11, 3}, {"REMOVE"}

.define EQUIP_STRENGTH                  BG3A, {16, 17}, {"Vigor"}
.define EQUIP_SPEED                     BG3A, {16, 19}, {"Speed"}
.define EQUIP_STAMINA                   BG3A, {16, 21}, {"Stamina"}
.define EQUIP_MAG_PWR                   BG3A, {16, 23}, {"Mag.Pwr"}
.define EQUIP_ATTACK_PWR                BG3A, {16, 25}, {"Bat.Pwr"}
.define EQUIP_DEFENSE                   BG3A, {16, 27}, {"Defense"}
.define EQUIP_EVADE                     BG3A, {16, 29}, {"Evade %"}
.define EQUIP_MAG_DEF                   BG3A, {16, 31}, {"Mag.Def"}
.define EQUIP_MAG_EVADE                 BG3A, {16, 33}, {"MBlock%"}
.define EQUIP_ARROW(yy)                 BG3A, {26, yy}, {"{rightarrow}"}

.define EQUIP_EMPTY_MSG                 BG3A, {13, 3}, {"Empty"}
.define EQUIP_OPTIMUM_MSG               BG3A, {12, 3}, {"Optimum"}
.define RELIC_EMPTY_MSG                 BG3A, {13, 5}, {"Empty"}
.define RELIC_OPTIMUM_MSG               BG3A, {12, 5}, {"Optimum"}
.define EQUIP_CHANGED_MSG               BG3A, {6, 7}, {"Equipment changed."}

; these are unused in the English translation
.define PARTY_EQUIP_SLOT1_RHAND         BG1A, {3, 4}, {$9f,$2d,$00}  ; みぎ
.define PARTY_EQUIP_SLOT1_LHAND         BG1A, {17, 4}, {$63,$3f,$a9,$00}  ; ひだり
.define PARTY_EQUIP_SLOT1_HEAD          BG1A, {3, 6}, {$8b,$7f,$9d,$00}  ; あたま
.define PARTY_EQUIP_SLOT1_BODY          BG1A, {17, 6}, {$6b,$a7,$3f,$00}  ; からだ
.define PARTY_EQUIP_SLOT1_RELIC1        BG1A, {3, 8}, {$8a,$6e,$54,$00}  ; アク１
.define PARTY_EQUIP_SLOT1_RELIC2        BG1A, {17, 8}, {$8a,$6e,$55,$00}  ; アク２

.define PARTY_EQUIP_SLOT2_RHAND         BG1A, {3, 12}, {$9f,$2d,$00}  ; みぎ
.define PARTY_EQUIP_SLOT2_LHAND         BG1A, {17, 12}, {$63,$3f,$a9,$00}  ; ひだり
.define PARTY_EQUIP_SLOT2_HEAD          BG1A, {3, 14}, {$8b,$7f,$9d,$00}  ; あたま
.define PARTY_EQUIP_SLOT2_BODY          BG1A, {17, 14}, {$6b,$a7,$3f,$00}  ; からだ
.define PARTY_EQUIP_SLOT2_RELIC1        BG1A, {3, 16}, {$8a,$6e,$54,$00}  ; アク１
.define PARTY_EQUIP_SLOT2_RELIC2        BG1A, {17, 16}, {$8a,$6e,$55,$00}  ; アク２

.define PARTY_EQUIP_SLOT3_RHAND         BG1A, {3, 20}, {$9f,$2d,$00}  ; みぎ
.define PARTY_EQUIP_SLOT3_LHAND         BG1A, {17, 20}, {$63,$3f,$a9,$00}  ; ひだり
.define PARTY_EQUIP_SLOT3_HEAD          BG1A, {3, 22}, {$8b,$7f,$9d,$00}  ; あたま
.define PARTY_EQUIP_SLOT3_BODY          BG1A, {17, 22}, {$6b,$a7,$3f,$00}  ; からだ
.define PARTY_EQUIP_SLOT3_RELIC1        BG1A, {3, 24}, {$8a,$6e,$54,$00}  ; アク１
.define PARTY_EQUIP_SLOT3_RELIC2        BG1A, {17, 24}, {$8a,$6e,$55,$00}  ; アク２

.define PARTY_EQUIP_SLOT4_RHAND         BG1A, {3, 28}, {$9f,$2d,$00}  ; みぎ
.define PARTY_EQUIP_SLOT4_LHAND         BG1A, {17, 28}, {$63,$3f,$a9,$00}  ; ひだり
.define PARTY_EQUIP_SLOT4_HEAD          BG1A, {3, 30}, {$8b,$7f,$9d,$00}  ; あたま
.define PARTY_EQUIP_SLOT4_BODY          BG1A, {17, 30}, {$6b,$a7,$3f,$00}  ; からだ
.define PARTY_EQUIP_SLOT4_RELIC1        BG1A, {3, 32}, {$8a,$6e,$54,$00}  ; アク１
.define PARTY_EQUIP_SLOT4_RELIC2        BG1A, {17, 32}, {$8a,$6e,$55,$00}  ; アク２

; ------------------------------------------------------------------------------

; party menu text strings

.define PARTY_LEVEL                     BG1A, {18, 8}, {"LV"}
.define PARTY_HP                        BG1A, {18, 10}, {"HP"}
.define PARTY_MP                        BG1A, {18, 12}, {"MP"}
.define PARTY_HP_SLASH                  BG1A, {25, 10}, {"/"}
.define PARTY_MP_SLASH                  BG1A, {25, 12}, {"/"}

.define PARTY_MSG                       BG1A, {10, 3}, {"Form   group(s).      "}
.define PARTY_TITLE                     BG1A, {2, 3}, {"Lineup"}
.define PARTY_ERROR_MSG1                BG1A, {10, 3}, {"You need   group(s)!"}
.define PARTY_ERROR_MSG2                BG1A, {10, 3}, {"No one there!       "}

; ------------------------------------------------------------------------------

; status menu text strings
.define STATUS_TITLE                    BG3A, {2, 2}, {"Status"}
.define STATUS_HP_SLASH                 BG1A, {17, 8}, {"/"}
.define STATUS_MP_SLASH                 BG1A, {17, 9}, {"/"}
.define STATUS_EVADE_PERCENT            BG3A, {29, 28}, {"%"}
.define STATUS_MAG_EVADE_PERCENT        BG3C, {29, 0}, {"%"}
.define STATUS_LEVEL                    BG1A, {10, 7}, {"LV"}
.define STATUS_HP                       BG1A, {10, 8}, {"HP"}
.define STATUS_MP                       BG1A, {10, 9}, {"MP"}
.define STATUS_STRENGTH                 BG3A, {3, 26}, {"Vigor"}
.define STATUS_STAMINA                  BG3A, {3, 30}, {"Stamina"}
.define STATUS_MAG_PWR                  BG3C, {3, 0}, {"Mag.Pwr"}
.define STATUS_EVADE                    BG3A, {16, 28}, {"Evade %"}
.define STATUS_MAG_EVADE                BG3C, {16, 0}, {"MBlock%"}
.define STATUS_STRENGTH_SEP             BG3A, {10, 26}, {"{2dot}"}
.define STATUS_SPEED_SEP                BG3A, {10, 28}, {"{2dot}"}
.define STATUS_STAMINA_SEP              BG3A, {10, 30}, {"{2dot}"}
.define STATUS_MAG_PWR_SEP              BG3C, {10, 0}, {"{2dot}"}
.define STATUS_DEFENSE_SEP              BG3A, {25, 26}, {"{2dot}"}
.define STATUS_EVADE_SEP                BG3A, {25, 28}, {"{2dot}"}
.define STATUS_ATTACK_PWR_SEP           BG3A, {25, 24}, {"{2dot}"}
.define STATUS_MAG_DEF_SEP              BG3A, {25, 30}, {"{2dot}"}
.define STATUS_MAG_EVADE_SEP            BG3C, {25, 0}, {"{2dot}"}
.define STATUS_SPEED                    BG3A, {3, 28}, {"Speed"}
.define STATUS_ATTACK_PWR               BG3A, {16, 24}, {"Bat.Pwr"}
.define STATUS_DEFENSE                  BG3A, {16, 26}, {"Defense"}
.define STATUS_MAG_DEF                  BG3A, {16, 30}, {"Mag.Def"}
.define STATUS_YOUR_EXP                 BG3A, {2, 16}, {"Your Exp:"}
.define STATUS_LEVEL_UP_EXP             BG3A, {2, 20}, {"For level up:"}

; ------------------------------------------------------------------------------

; shop menu text strings
.define SHOP_TYPE_1                     BG3A, {2, 3}, {"Weapon"}
.define SHOP_TYPE_2                     BG3A, {3, 3}, {"Armor"}
.define SHOP_TYPE_3                     BG3A, {3, 3}, {"Item"}
.define SHOP_TYPE_4                     BG3A, {2, 3}, {"Relics"}
.define SHOP_TYPE_5                     BG3A, {2, 3}, {"Vendor"}
.define SHOP_OPTIONS                    BG3A, {3, 7}, {"BUY  SELL  EXIT"}
.define SHOP_GIL_1                      BG3A, {28, 7}, {"GP"}
.define SHOP_GIL_2                      BG3A, {17, 11}, {"GP"}
.define SHOP_OWNED                      BG3A, {21, 9}, {"Owned:"}
.define SHOP_EQUIPPED                   BG3A, {21, 13}, {"Equipped:"}
.define SHOP_POWER                      BG3A, {3, 13}, {"Bat Pwr"}
.define SHOP_DEFENSE                    BG3A, {3, 13}, {"Defense"}
.define SHOP_DOTS                       BG3A, {14, 13}, {"_"}
.define SHOP_GREETING_MSG               BG3A, {11, 3}, {"Hi! Can I help you?"}
.define SHOP_BUY_MSG                    BG3A, {11, 3}, {"Help yourself!"}
.define SHOP_BUY_QTY_MSG                BG3A, {11, 3}, {"How many?"}
.define SHOP_SELL_MSG                   BG3A, {11, 3}, {"Whatcha got?"}
.define SHOP_SELL_QTY_MSG               BG3A, {11, 3}, {"How many?"}
.define SHOP_BYE_MSG                    BG3A, {11, 3}, {"Bye!          "}
.define SHOP_NOT_ENOUGH_GIL_MSG         BG3A, {11, 3}, {"You need more GP!"}
.define SHOP_TOO_MANY_MSG               BG3A, {11, 3}, {"Too many!       "}
.define SHOP_ONLY_ONE_MSG               BG3A, {11, 3}, {"One's plenty! "}

; ------------------------------------------------------------------------------

; config menu text strings
.define CONFIG_COLOR_ARROW_BLANK        BG1B, {22, 18}, {"       "}
.define CONFIG_COLOR_ARROW(xx)          BG1B, {xx, 18}, {"{uparrow}"}

.define CONFIG_CONTROLLER               BG1A, {3, 21}, {"Controller"}
.define CONFIG_WAIT                     BG1A, {22, 5}, {"Wait"}
.define CONFIG_FAST                     BG1A, {14, 8}, {"Fast"}
.define CONFIG_SLOW                     BG1A, {22, 8}, {"Slow"}
.define CONFIG_CMD_SHORT                BG1A, {22, 11}, {"Short"}
.define CONFIG_GAUGE_ON                 BG1A, {14, 13}, {"On"}
.define CONFIG_GAUGE_OFF                BG1A, {22, 13}, {"Off"}
.define CONFIG_STEREO                   BG1A, {14, 15}, {"Stereo"}
.define CONFIG_MONO                     BG1A, {22, 15}, {"Mono"}
.define CONFIG_MEMORY                   BG1A, {22, 17}, {"Memory"}
.define CONFIG_OPTIMUM                  BG1A, {14, 19}, {"Optimum"}
.define CONFIG_CTRL_MULTI               BG1A, {22, 21}, {"Multiple"}
.define CONFIG_BATTLE_SPEED_NUM         BG1A, {14, 7}, {"1 2 3 4 5 6"}
.define CONFIG_MSG_SPEED_NUM            BG1A, {14, 9}, {"1 2 3 4 5 6"}
.define CONFIG_CURSOR                   BG1A, {3, 17}, {"Cursor"}

.define CONFIG_TITLE                    BG3A, {24, 2}, {"Config"}
.define CONFIG_BATTLE_MODE              BG1A, {3, 5}, {"Bat.Mode"}
.define CONFIG_BATTLE_SPEED             BG1A, {3, 7}, {"Bat.Speed"}
.define CONFIG_MSG_SPEED                BG1A, {3, 9}, {"Msg.Speed"}
.define CONFIG_CMD_SET                  BG1A, {3, 11}, {"Cmd.Set"}
.define CONFIG_GAUGE                    BG1A, {3, 13}, {"Gauge"}
.define CONFIG_SOUND                    BG1A, {3, 15}, {"Sound"}
.define CONFIG_REEQUIP                  BG1A, {3, 19}, {"Reequip"}
.define CONFIG_ACTIVE                   BG1A, {14, 5}, {"Active"}
.define CONFIG_CMD_WINDOW               BG1A, {14, 11}, {"Window"}
.define CONFIG_RESET                    BG1A, {14, 17}, {"Reset"}
.define CONFIG_EMPTY                    BG1A, {22, 19}, {"Empty"}
.define CONFIG_CTRL_SINGLE              BG1A, {14, 21}, {"Single"}

.define CONFIG_MAGIC_ORDER              BG1B, {3, 5}, {"Mag.Order"}
.define CONFIG_WINDOW_LABEL             BG1B, {3, 13}, {"Window"}
.define CONFIG_COLOR                    BG1B, {3, 15}, {"Color"}
.define CONFIG_MAGIC_ORDER_A            BG1B, {14, 7}, {"A{2dot}"}
.define CONFIG_MAGIC_ORDER_B            BG1B, {14, 9}, {"B{2dot}"}
.define CONFIG_MAGIC_ORDER_C            BG1B, {14, 11}, {"C{2dot}"}
.define CONFIG_COLOR_BAR_R              BG1B, {18, 19}, {"{gauge_left}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_right}"}
.define CONFIG_COLOR_BAR_G              BG1B, {18, 21}, {"{gauge_left}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_right}"}
.define CONFIG_COLOR_BAR_B              BG1B, {18, 23}, {"{gauge_left}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_empty}{gauge_right}"}
.define CONFIG_COLOR_R                  BG1B, {14, 19}, {"R"}
.define CONFIG_COLOR_G                  BG1B, {14, 21}, {"G"}
.define CONFIG_COLOR_B                  BG1B, {14, 23}, {"B"}
.define CONFIG_WINDOW_NUM               BG1B, {14, 13}, {"1 2 3 4 5 6 7 8"}
.define CONFIG_MAGIC_ORDER_NUM          BG1B, {14, 5}, {"1 2 3 4 5 6"}
.define CONFIG_FONT                     BG1B, {14, 15}, {"Font"}
.define CONFIG_WINDOW                   BG1B, {22, 15}, {"Window"}

.define CONFIG_RETURN                   BG1B, {25, 14}, {$a5,$47,$79,$00}  ; もどす (Return)
.define CONFIG_COLOR_BOX                BG1B, {22, 17}, {"{1}{2}{3}{4}{5}{6}{7}"}
.define CONFIG_MAGIC_TYPE_1             {z"{white}Healing  "}
.define CONFIG_MAGIC_TYPE_2             {z"{black}Attack   "}
.define CONFIG_MAGIC_TYPE_3             {z"{effect}Effect   "}

.define CMD_ARRANGE_TITLE               BG3A, {3, 2}, {"Arrange"}

.define CHAR_CTRL_TITLE                 BG3A, {2, 12}, {"Controller"}
.define CHAR_1_CTRL_1                   BG3A, {12, 15}, {"Cntlr1"}
.define CHAR_1_CTRL_2                   BG3A, {21, 15}, {"Cntlr2"}
.define CHAR_2_CTRL_1                   BG3A, {12, 17}, {"Cntlr1"}
.define CHAR_2_CTRL_2                   BG3A, {21, 17}, {"Cntlr2"}
.define CHAR_3_CTRL_1                   BG3A, {12, 19}, {"Cntlr1"}
.define CHAR_3_CTRL_2                   BG3A, {21, 19}, {"Cntlr2"}
.define CHAR_4_CTRL_1                   BG3A, {12, 21}, {"Cntlr1"}
.define CHAR_4_CTRL_2                   BG3A, {21, 21}, {"Cntlr2"}

; ------------------------------------------------------------------------------

; save menu text strings
.define SAVE_SLOT_1_EMPTY               BG3A, {3, 8}, {"Empty"}
.define SAVE_SLOT_2_EMPTY               BG3A, {3, 15}, {"Empty"}
.define SAVE_SLOT_3_EMPTY               BG3A, {3, 22}, {"Empty"}
.define SAVE_SLOT_1_TIME                BG3A, {3, 10}, {"Time"}
.define SAVE_SLOT_2_TIME                BG3A, {3, 17}, {"Time"}
.define SAVE_SLOT_3_TIME                BG3A, {3, 24}, {"Time"}
.define SAVE_SLOT_1_TIME_COLON          BG3A, {4, 11}, {":"}
.define SAVE_SLOT_2_TIME_COLON          BG3A, {4, 18}, {":"}
.define SAVE_SLOT_3_TIME_COLON          BG3A, {4, 25}, {":"}
.define SAVE_SLOT_1_LEVEL               BG3A, {25, 8}, {"LV"}
.define SAVE_SLOT_2_LEVEL               BG3A, {25, 15}, {"LV"}
.define SAVE_SLOT_3_LEVEL               BG3A, {25, 22}, {"LV"}
.define SAVE_SLOT_1_HP_SLASH            BG3A, {25, 10}, {"/"}
.define SAVE_SLOT_2_HP_SLASH            BG3A, {25, 17}, {"/"}
.define SAVE_SLOT_3_HP_SLASH            BG3A, {25, 24}, {"/"}

.define SAVE_TITLE                      BG3A, {15, 4}, {"Save"}
.define NEW_GAME_TITLE                  BG3A, {13, 4}, {"New Game"}

; ------------------------------------------------------------------------------

; element symbols
.define ELEMENT_SYMBOLS                 {b"{water}{earth}{holy}{wind}{poison}{lightning}{ice}{fire}"}

; ------------------------------------------------------------------------------

; name change menu text
.define NAME_CHANGE_MSG                 BG1B, {9, 3}, {"Please enter a name."}

.define NAME_CHANGE_LETTERS_1           {z"ABCDEabcde"}
.define NAME_CHANGE_LETTERS_2           {z"FGHIJfghij"}
.define NAME_CHANGE_LETTERS_3           {z"KLMNOklmno"}
.define NAME_CHANGE_LETTERS_4           {z"PQRSTpqrst"}
.define NAME_CHANGE_LETTERS_5           {z"UVWXYuvwxy"}
.define NAME_CHANGE_LETTERS_6           {z"Z!?/:z”'-."}
.define NAME_CHANGE_LETTERS_7           {z"0123456789"}

; ------------------------------------------------------------------------------

; final order menu text strings
.define FINAL_ORDER_END                 BG1A, {4, 31}, {"End"}
.define FINAL_ORDER_RESET               BG1A, {4, 5}, {"Reset"}
.define FINAL_ORDER_MSG                 BG1A, {10, 3}, {"Determine order"}

; ------------------------------------------------------------------------------

.endif
