/* ot6 C spike: smallest observable function. the trampoline
   (Ot6CSpikeProbe, ff6/src/battle/ot6.asm) stores the result at the
   witness word OT6_CWITNESS = $7e57ba, where battle_c.lua asserts it.
   ($57ba sits in the write-watch-verified free strip next to
   OT6_FONTDIRTY; the old home $57dc was inside vanilla's $57d5-$5854
   battle name-scratch string.) */
unsigned char ot6_c_mix(unsigned char a, unsigned char b)
{
    return (unsigned char)(a * 2 + b + 1);
}
