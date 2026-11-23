"""pins_suite.py -- the break-row suites' proofs as pins (the battle_break* suites agent's proposal-2,
build/attempts/wt/v051-six-classes/breaksuites/proposal-2/pins-suite.py, taken as it stands)."""
S, P, B, X = 1, 2, 4, 8
# the break-row suites' proofs as pins (propose.py): SUITE entries are merged over pins.PIN (a kind given
# here replaces PIN's for that weakness; source "suite ..." binds), EVERY's keys join pins.EVERY (all six;
# Siegfried's four-class row is three classes, so split.assign's `old == 15` test must go), DEPARTURE lists
# the pins outside classes.py CHILDREN
EVERY = {
    0x012a: "route-wor-the-end.md, battle_breakwor_end 'Kefka: class mask, want every hand'",
}
SUITE = {
    # the opening's species are not here: pins.OPENING authors their whole rows (docs/design/opening.md), and
    # these entries, the suites' proofs with the automated route's hands, were taken out as it settled each:
    #   $023 FossilFang  suite pierce->Spear (EDGAR's pike): kept, Spear|Blunt
    #   $015 Rhinotaur   suite pierce->Spear (EDGAR's pike): Ranged|Blunt; a new player's EDGAR holds no pike
    #                    before Narshe's shop (the route strips MOG's), so the bolt is his point
    #   $022 Pterodon, $038 Nautiloid, $039 Exocite  suite "on the raft each of TERRA's blade, EDGAR's pike and
    #                    BANON's rod keys two of the three": kept with the AutoCrossbow in the pike's place
    #                    (Sword|Ranged, Ranged|Blunt, Sword|Blunt)
    #   $065 Trooper, $01C Fidor, $079 Bounty Man  suite Sword|Dagger: kept, with Katana a third (any squad)
    #   $09F HeavyArmor  suite Sword|Dagger: Dagger alone (three elements leave the HUD's four cells one)
    #   $131 Siegfried   suite "every weapon hand" (EVERY, all six): the three hands of the party that meets
    #                    him, Dagger|Katana|Blunt (six classes do not fit the HUD's four cells)
    # the World of Balance past the opening
    0x007b: ({S: 'sword'}, "suite battle_breakwob_south: the blades (TERRA's Break Blade, LOCKE's ThunderBlade) key every body"),
    0x0081: ({S: 'sword'}, "suite battle_breakwob_south: the blades (TERRA's Break Blade, LOCKE's ThunderBlade) key every body"),
    0x008d: ({S: 'sword'}, "suite battle_breakwob_south: the blades (TERRA's Break Blade, LOCKE's ThunderBlade) key every body"),
    # the World of Ruin
    0x005b: ({P: 'ninja blade'}, "suite battle_breakwor_colosseum: among the four's blades, SHADOW's (the Striker) "
             "alone keys the Crawler"),
    0x0027: ({P: 'ninja blade'}, "suite battle_breakwor_sidetrips: SHADOW's point (the Striker) keys both dinosaurs"),
    0x0026: ({P: 'ninja blade'}, "suite battle_breakwor_sidetrips: SHADOW's point (the Striker) keys both dinosaurs"),
    0x014b: ({S: 'katana', P: 'sword'}, "suite battle_breakwor_cyan: CYAN's katana keys the Storm Dragon, and each of "
             "the four who fight it holds a key (TERRA's Enhancer)"),
    0x0004: ({S: 'katana', P: 'sword'}, "suite battle_breakwor_dreams: CYAN alone keys every body of the Ancient "
             "Castle, and the dream's three (TERRA, CELES, RELM) hold a key in the dream's Doma"),
    0x00be: ({S: 'sword', X: 'katana'}, "suite battle_breakwor_dreams: TERRA alone keys every body of the dreamscape, "
             "and CYAN alone every body of the Ancient Castle"),
    0x00c3: ({S: 'sword'}, "suite battle_breakwor_edgar: a key for CELES + SABIN (her swords)"),
    0x011b: ({S: 'sword'}, "suite battle_breakwor_edgar: each member holds a class key on three of the four Tentacles"),
    0x013c: ({S: 'sword', B: 'knuckle'}, "suite battle_breakwor_edgar: each member holds a class key on three of the "
             "four Tentacles"),
    0x013d: ({P: 'spear', B: 'knuckle'}, "suite battle_breakwor_edgar: each member holds a class key on three of the "
             "four Tentacles (CELES's swords miss this one, the design's one)"),
    0x013e: ({S: 'sword', P: 'knuckle'}, "suite battle_breakwor_edgar: each member holds a class key on three of the "
             "four Tentacles"),
    0x007e: ({B: 'fang'}, "suite battle_breakwor_gau: GAU alone holds a key to every body of the Veldt cave"),
    0x008f: ({P: 'fang'}, "suite battle_breakwor_gau: GAU alone holds a key to every body of the Veldt cave"),
    0x00bb: ({B: 'fang'}, "suite battle_breakwor_gau: GAU alone holds a key to every body of the Veldt cave"),
    0x0119: ({P: 'fang'}, "suite battle_breakwor_gau: GAU alone holds a key to every body of the Veldt cave"),
    0x00f0: ({S: 'sword', B: 'rod'}, "suite battle_breakwor_gogo: every belly body is keyed by two of the four who walk it"),
    0x0068: ({S: 'sword', P: 'dagger'}, "suite battle_breakwor_gogo: every belly body is keyed by two of the four who "
             "walk it"),
    0x00f1: ({S: 'sword', X: 'rod'}, "suite battle_breakwor_locke: a key for party 2 (CELES's Falchion; RELM's rod, "
             "UMARO's club)"),
    0x00e2: ({B: 'rod'}, "suite battle_breakwor_locke: ice-weak, and party 1 (no ice) has a key (STRAGO's rod, SABIN's "
             "blitzes)"),
    0x009e: ({P: 'spear'}, "suite battle_breakwor_narshe: a key for the four with MOG (his spear)"),
    0x00e7: ({P: 'spear'}, "suite battle_breakwor_narshe: a key for the four with MOG (his spear)"),
    0x00f3: ({P: 'spear'}, "suite battle_breakwor_narshe: a key for the four with MOG (his spear)"),
    0x0087: ({S: 'sword'}, "suite battle_breakwor_narshe: a key for the four with UMARO (TERRA's and CELES's blades)"),
    0x00fb: ({S: 'sword', P: 'dagger'}, "suite battle_breakwor_tower: a key for each party whose lane meets it "
             "(parties 1 and 2 a sword, party 3 SHADOW's and GOGO's blades)"),
    0x00e0: ({P: 'dagger', B: 'rod'}, "suite battle_breakwor_tower: a key for each party whose lane meets it (parties "
             "1 and 2 a rod, party 3 SHADOW's and GOGO's blades)"),
    0x009b: ({S: 'katana', P: 'dagger'}, "suite battle_breakwor_tower: a key for party 3 (CYAN's katanas, SHADOW's "
             "Striker)"),
    0x0007: ({S: 'katana', B: 'rod'}, "suite battle_breakwor_tower: a key for each party whose lane meets it (parties "
             "1 and 2 a rod, party 3 CYAN's katanas)"),
}
# pins that name a class outside what the four-class weakness's own weapons went to (classes.py CHILDREN), and why
DEPARTURE = {
    0x014b: "pierce -> Sword: slash was TERRA's blade and CYAN's katana at once; the katana keeps slash (the lesson), "
            "so TERRA's sword takes the row's other weakness",
    0x0004: "pierce -> Sword: slash was TERRA's and CELES's blades (the dream's Doma) and CYAN's katana (alone at "
            "the Ancient Castle) at once",
    0x00be: "special -> Katana: slash was TERRA's blade (alone in the dreamscape) and CYAN's katana (alone at the "
            "Ancient Castle) at once",
    0x013e: "pierce -> Blunt: SABIN's knuckles were slash and keyed the three slash Tentacles; Blunt is a child of "
            "bludgeon only, which two of the four Tentacles have",
    0x007e: "bludgeon -> Dagger: the Veldt cave's rows keyed bludgeon for GAU's fists, and his own body is his fangs now",
    0x00bb: "bludgeon -> Dagger: the Veldt cave's rows keyed bludgeon for GAU's fists, and his own body is his fangs now",
}
