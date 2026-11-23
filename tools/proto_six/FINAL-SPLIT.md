# The split is final (origin/wt/v051-six-classes 84b3bae0, ROM identity ac057dac6cf8, CRC 0xD9D62041)

Merge 84b3bae0. What it holds beyond tools/proto_six/REGROUP.md:

- The rows: split.py run once more in full with every pin: the opening authored by hand (pins.OPENING, 85
  species, docs/design/opening.md: read it, it restates bosses 1-11 and the first hours), the WoB stories, the
  break-row suites' proofs (pins_suite.py = the suites agent's proposal-4, less Umaro's ADD), the holder rule, the
  route's real hands, then balance. `python3 tools/proto_six/split.py --report-only` prints every row and why
  (also build/attempts/wt/v051-six-classes/split-report-final.txt). From here a row changes only by an edit to
  the pins and `python3 tools/proto_six/split.py --keep HEAD` (which recomputes nothing else).
- Counts changed on purpose in places: the opening has 12 rows with one more weakness and 3 with fewer
  (opening.md "Departures"); ADD gives the Bogy $0D3 Blunt, Tritoch $144 and the Long Arm $158 Katana; EVERY rows
  (Intangir $0A3, Speck $146, Siegfried $131, Kefka $12A all six; the Girl $15E every class her slash|pierce went
  to). Ot6ClassSplitTbl now holds shapes the mechanical split never made: two bits in one byte (Lobo's pierce is
  $22), $00 for a four-class weakness with no child in the row, and row bits no four-class save reveals.
- HUD: a body whose row is all six classes draws ONE cell for its classes, the any-weapon mark OT6_ANYWEAPON = $df
  ('?' until any class is revealed). Other bodies with elements+classes over four still lose the overflow.
- Text: the Narshe school's weapon page ($0264) is four new pages (seven in all; tools/tests/school_bytes.py
  must be re-run); narshe-school.md is updated.
- The floor follows the rows (gen_break_floor.py: a rowed species takes its row's lowest class bit).
- Save codex: O9, Ot6ClassSplitTbl four bytes a species; the saves agent's suites read the table from the ROM.

A replay of the whole line on this ROM is filling mbp.local:work/ot6-proto-six (build/states); the earlier
states there were deleted. A baseline of main's line with the same instrument is in
mbp.local:work/ot6-proto-six-base (four-class ROM; not for your suites).
