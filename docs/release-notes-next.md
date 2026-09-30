# OT6 next release — notes in progress

Player-facing changes merged since the last release, one paragraph each, in
play terms. Each commit that adds a line names its evidence in the commit
message. At release this file becomes `release-notes-vX.Y.md` with the
title, the how-to-play section and the save note from the previous
release's notes.

## What's changed

**The World of Ruin from Tzen to Edgar has designed break weaknesses.**
The monsters between Tzen and Nikeah, around South Figaro, in the Figaro
cave and in the castle's basements used to carry generic weaknesses and
five or six shields, so a break usually landed on a monster that was
already dying. Now each one is designed around Celes and Sabin: one to
four shields, weak to their blades and fists. The armored Bloompire breaks
to one blade hit, and a broken Bloompire gets no turn to turn someone into
a zombie; breaking the Dante stops its confusing counter. The four Tentacles in
the engine room have five shields each and absorb fire, ice or lightning
between them, so blades, fists and Edgar's crossbow break them, not
spells.

**A monster you break loses the turn it was about to take.** When a
monster's turn was already lined up and you broke it just before it
acted, it used to take that turn anyway, attack and all. Now it loses
that turn too: a broken monster gets no turns until its shields come
back.

**A boosted Dance stays boosted for the whole dance.** Boosting Mog's
Dance used to multiply only its first step; every step after that hit
for normal damage, although the boost's pips and MP had been paid. Now
every step of that dance hits for the boosted amount (x2, x4 or x8)
until the dance ends. The price is unchanged, paid once when the dance
starts.

**A Dance that stumbles costs nothing.** Away from its own terrain, a
Dance still stumbles half the time, as in the original. A stumble used to
take the Dance's MP and any boost pips even though no dance started. Now
a stumble costs no MP and no pips, and Mog gains his pip for the turn as
he would after any unboosted action.

**Terra and Celes learn short spell lists, Espers give short ones, and stronger
spells come only from boosting.** Nobody learns Fire 2, Ice 3, Cure 2 or any
other stronger version by level, and no Esper gives one: boost the plain
spell to cast it. Terra knows Fire and Cure when she joins and learns Drain
(level 12), Life (18), Break (24), Pearl (30) and Merton (33). Celes knows
Ice when she joins and learns Cure (4), Imp (13), Scan (18), Safe (22) and
Haste (32). Equipped Espers now give: Siren Mute and Sleep; Stray Muddle and
Imp; Kirin Cure and Regen; ZoneSeek Shell and Haste; Sraphim Cure and Life;
Golem Safe (the World of Ruin's Espers are below). Saves from earlier
versions may keep spells their characters already learned.

**The World of Ruin's Espers give new lists, and Life boosts to Life 3.**
Equipped, Palidor gives Float and Slow; Fenrir Stop and X-Zone; Starlet
Cure, Regen and Remedy; Alexandr Dispel, Safe and Shell; Terrato Quake and
Quartr; Tritoch Ice, Bolt and Poison; Odin Meteor and Bserk; Raiden
Meteor, Bserk and Quick; Bahamut Flare and W Wind; Phoenix Life and Antdot;
Ragnarok Ultima and Warp; Crusader Merton and Meteor. Boosting Life by one
point casts Life 2, and by two points Life 3, for 60 MP. Cast by your
party, Life 3 works on a fallen ally too: it brings them back at full HP and
protects them, so they rise again once the next time they fall. On a
standing ally it gives only that protection.

**The shield under a monster shows its true count above 6.** A boss with
more than six shields used to show 6 until enough had been broken; Number 024
now shows 7, and AtmaWeapon 11. From 10 up the count is two white numerals
on a dark shield.

**The Beginner's House no longer repeats how to use Blitz.** Sabin's first
battle against Vargas walks you through it, where you first need it.

**Vargas: Pummel finishes him even while he is Broken.** Before, if
Sabin's Pummel broke Vargas, or landed while he was already Broken, the
fight simply went on, and only a Pummel after he recovered ended it.
Now any Pummel ends the fight, Broken or not. The same rule covers every
boss whose story ends the battle on a counter: a Broken boss still loses
its counterattacks, but not the scene that ends the fight. At Esper Mountain, Relm now arrives
when her cue comes even if Ultros is Broken.
