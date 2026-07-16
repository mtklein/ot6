/* ot6 C spike: smallest observable function. the trampoline stores the
   result where the harness can assert it. */
unsigned char ot6_c_mix(unsigned char a, unsigned char b)
{
    return (unsigned char)(a * 2 + b + 1);
}
