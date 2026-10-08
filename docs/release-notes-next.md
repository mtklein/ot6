# OT6 next release — notes in progress

Player-facing changes merged since the last release, one paragraph each, in
play terms. Each commit that adds a line names its evidence in the commit
message. At release this file becomes `release-notes-vX.Y.md` with the
title, the how-to-play section and the save note from the previous
release's notes.

## What's changed

**The Phantom Train: four shields, more HP -- and yes, Suplex.** The
train now carries four shields instead of six over more HP, so a party
that spends its Boost Points can break it (and give Cyan his first Cleave)
before it falls. And Sabin's Suplex on the train wins the fight on the
spot, the classic FF6 joke made true; it works on that train and nothing
else.

**A bigger boosted hit is never a smaller one.** A Boost Point's doubling
used to roll over to a lower number when a very strong attack doubled past
the game's internal limit, so against a heavily armored or Shelled enemy a
boosted blow could land for less than a weaker one. Boosted damage now
holds at the top instead; the usual 9,999 cap per hit is unchanged.

**More monsters fear cards, dice and brushes.** Special weapons (Setzer's
cards and dice, Relm's brushes) now break more of the spirits and magical
creatures you meet: the Pm Stalker in Tzen's collapsing house, the
NeckHunter and Dante in the cave to Figaro Castle, the spirits of the
Sealed Gate cave, and the Apokryphos, Misfit and Brainpan of the Floating
Continent. Each keeps every weakness it had.

**A boosted Magicite always calls an Esper worth the boost.** Using a
Magicite with Boost Points no longer wastes them on an Esper that does no
damage (Siren, Golem, Fenrir and the rest), passes over Phoenix (whose
revival gains nothing from boosting), and it no longer
calls Crusader, whose boosted Purifier wiped your own party. A boosted
Magicite now calls an Esper that strikes the enemy, or a healing one,
and the boost multiplies it. Unboosted, Magicite is the same gamble as
ever, Crusader included.

**Combat plans keep their aim and Boost Points.** Experimental combat choices
back out and reconsider when the highlighted target differs from the plan,
and healing items clear leftover pending boost before confirmation. A rejected
experimental command returns to ordinary combat choices for that battle.
