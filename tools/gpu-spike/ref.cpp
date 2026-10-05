// ref.cpp -- the CPU reference run: one instance of core.h on the host,
// checked against Mesen's trace at every frame (registers and 128 WRAM
// block hashes at each NMI), every I/O read (computed ALU and pad values
// against what Mesen returned) and the PC of every instruction in the
// first pc_frames frames.  Also saves per-frame checkpoints for the GPU's
// staggered-start runs.
//
//   ref <capture dir> <rom> [checkpoint out file] [n checkpoints]
#include <chrono>
#include <vector>
#include <cstdio>

#include <cstdint>
struct IoSeen { uint32_t icount, addr, value; };
static std::vector<IoSeen>* g_seen;
static uint32_t hook(uint32_t icount, uint32_t addr, uint32_t v) { g_seen->push_back({icount, addr, v}); return v; }
#define IO_HOOK(s, addr, v) hook((s).icount + 1, (addr), (v))
#include "replay.h"

int main(int argc, char** argv) {
  if (argc < 3) { fprintf(stderr, "usage: ref <capture dir> <rom> [ckpt out] [n ckpt]\n"); return 2; }
  Capture cap = load_capture(argv[1], argv[2]);
  const char* ckptOut = argc > 3 ? argv[3] : nullptr;
  u32 nCkpt = argc > 4 ? (u32)atoi(argv[4]) : 0;
  std::vector<u32> dec(256);
  build_decode(dec.data());
  for (int i = 0; i < 256; i++) if (dec[i] >> 31) { fprintf(stderr, "opcode %02X undecoded\n", i); return 2; }

  std::vector<u8> wram = cap.wram, sram = cap.sram;
  std::vector<IoSeen> seen;
  g_seen = &seen;
  Ctx c;
  c.wram = wram.data(); c.sram = sram.data(); c.rom = cap.rom.data(); c.map = cap.map.data();
  c.nmi_at = cap.nmi_at.data(); c.n_nmi = (u32)cap.nmi_at.size();
  c.io_at = cap.io_at.data(); c.io_val = cap.io_val.data(); c.n_io = (u32)cap.io_at.size();
  c.pad = cap.pad.data();
  c.stride = 1; c.sram_mask = (u32)sram.size() - 1;
  c.io_check = 1;
  Cpu s = initial_cpu(cap);

  printf("capture: %zu frames, %u instructions, %zu replayed reads, %zu io records, pc trace %zu (%u frames)\n",
         cap.nmi_at.size(), cap.nmi_at.empty() ? 0 : cap.nmi_at.back(), cap.io_at.size(), cap.io.size(),
         cap.pcs.size(), cap.pc_frames);

  // checkpoints: Cpu + WRAM + SRAM at the first nCkpt frame starts
  FILE* ck = ckptOut ? fopen(ckptOut, "wb") : nullptr;
  auto save_ckpt = [&]() {
    if (!ck || s.frame >= nCkpt) return;
    fwrite(&s, sizeof s, 1, ck);
    fwrite(wram.data(), 1, wram.size(), ck);
    fwrite(sram.data(), 1, sram.size(), ck);
  };
  save_ckpt();

  u32 frames_ok = 0, first_bad = 0xFFFFFFFF;
  size_t pc_bad = 0, pc_checked = 0;
  auto t0 = std::chrono::steady_clock::now();
  uint64_t instrs = 0;
  bool stop = false;
  while (!stop && s.frame < c.n_nmi) {
    if (s.icount < cap.pcs.size()) {
      pc_checked++;
      u32 want = cap.pcs[s.icount], got = (s.k << 16) | s.pc;
      if (want != got && pc_bad++ == 0)
        printf("FIRST PC DIVERGENCE at instruction %u: Mesen %06X, replay %06X (%s)\n",
               s.icount + 1, want, got, fmt_cpu(s).c_str());
    }
    step(s, c, dec.data());
    instrs++;
    if (s.status) {
      printf("stopped: status %u info %08X at instruction %u frame %u (%s)\n", s.status, s.info, s.icount, s.frame, fmt_cpu(s).c_str());
      break;
    }
#ifdef MUT_WRAM
    if (s.frame == 300 && s.icount == cap.nmi_at[299] + 1000) wram[0x1F00] ^= 1;  // negative control
#endif
    if (maybe_nmi(s, c)) {
      const IntEv& e = cap.ints[s.frame - 1];
      u32 h[128];
      wram_hashes(wram.data(), 1, h);
      int badBlocks = 0, firstBlock = -1;
      for (int b = 0; b < 128; b++) if (h[b] != e.hash[b]) { if (firstBlock < 0) firstBlock = b; badBlocks++; }
      bool rok = regs_match(s, e.regs);
      if (rok && badBlocks == 0) { if (first_bad == 0xFFFFFFFF) frames_ok++; }
      else if (first_bad == 0xFFFFFFFF) {
        first_bad = s.frame;
        printf("FIRST FRAME DIVERGENCE at frame %u (NMI after instruction %u): regs %s; %d WRAM blocks differ (first $%05X)\n",
               s.frame, s.icount, rok ? "match" : "DIFFER", badBlocks, firstBlock * 1024);
        if (!rok) printf("  Mesen  %s\n  replay %s\n", fmt_regs(e.regs).c_str(), fmt_cpu(s).c_str());
        stop = true;
      }
      save_ckpt();
    }
  }
  double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

  // I/O reads: what the replay returned vs what Mesen returned, in order
  std::vector<IoEv> want;
  for (auto& e : cap.io) if (e.tag == 'R' && e.icount <= s.icount) want.push_back(e);
  size_t n = std::min(want.size(), seen.size()), io_bad = 0;
  std::map<u32, std::pair<u32, u32>> perAddr;  // addr -> (count, bad)
  for (size_t i = 0; i < n; i++) {
    u32 a = want[i].addr & 0xFFFF;
    auto& pa = perAddr[a];
    pa.first++;
    bool ok = want[i].icount == seen[i].icount && (want[i].addr & 0xFFFF) == (seen[i].addr & 0xFFFF) && want[i].value == seen[i].value;
    if (!ok) {
      pa.second++;
      if (io_bad++ < 5)
        printf("io read %zu differs: Mesen #%u $%04X=%02X, replay #%u $%04X=%02X\n", i, want[i].icount,
               want[i].addr & 0xFFFF, want[i].value, seen[i].icount, seen[i].addr & 0xFFFF, seen[i].value);
    }
  }
  printf("io reads: Mesen %zu, replay %zu, compared %zu, differing %zu\n", want.size(), seen.size(), n, io_bad);
  for (auto& kv : perAddr) printf("  $%04X: %u reads, %u differ\n", kv.first, kv.second.first, kv.second.second);
  printf("pc trace: %zu instructions compared, %zu differ\n", pc_checked, pc_bad);
  printf("frames bit-exact (registers + all 128 WRAM block hashes at each NMI): %u of %u\n", frames_ok, c.n_nmi);
  printf("reference: %llu instructions, %u frames in %.3f s = %.0f instr/s, %.1f frames/s (one host core)\n",
         (unsigned long long)instrs, s.frame, secs, instrs / secs, s.frame / secs);
  if (ck) fclose(ck);
  return (first_bad == 0xFFFFFFFF && io_bad == 0 && pc_bad == 0 && s.frame == c.n_nmi) ? 0 : 1;
}
