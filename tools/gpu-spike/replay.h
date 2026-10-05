// replay.h -- host side: load capture.lua's blobs and the ROM, build the
// memory map, the interrupt schedule, the replayed-read stream and the
// per-frame pad words.  Blob formats (all little-endian):
//
// gpu_init.bin  "GPUI" u32 nregs u32 sramSize u32 textLen
//               regs (REGS below) | WRAM 128KB | SRAM | getState() as k=v text
// gpu_trace.bin "GPUT" u32 nEvents u32 nPcs u32 pcFrames | u32 pcs[nPcs] | events
//   event 'R'/'W': u8 tag u32 icount u32 addr u8 value
//   event 'N'/'I': u8 tag u32 icount REGS u32 hash[128]
// REGS: u16 a x y sp d, u8 dbr k, u16 pc, u8 ps emu, u64 cycles (24 bytes)
// icount on R/W is the 1-based number of the instruction doing the access;
// on N/I it is the number of instructions before the interrupt was taken.
#pragma once
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include "core.h"

struct Regs { u16 a, x, y, sp, d; u8 dbr, k; u16 pc; u8 ps, emu; uint64_t cycles; };
struct IoEv { char tag; u32 icount, addr; u8 value; };
struct IntEv { char tag; u32 icount; Regs regs; u32 hash[128]; };

struct Capture {
  Regs init;
  std::vector<u8> wram, sram, rom;
  std::map<std::string, std::string> kv;
  std::vector<u32> pcs;
  u32 pc_frames = 0;
  std::vector<IoEv> io;     // every recorded I/O read and write
  std::vector<IntEv> ints;  // every interrupt after the start
  // derived
  std::vector<u32> map;     // 4096 entries
  std::vector<u32> nmi_at;
  std::vector<u32> io_at, io_val;
  std::vector<u16> pad;     // per frame
};

static std::vector<u8> slurp(const std::string& path) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); exit(2); }
  std::vector<u8> b;
  u8 buf[1 << 16];
  size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
  fclose(f);
  return b;
}

template <typename T> static T rd(const std::vector<u8>& b, size_t& o) {
  T v; memcpy(&v, &b[o], sizeof v); o += sizeof v; return v;
}

static Regs rd_regs(const std::vector<u8>& b, size_t& o) {
  Regs r;
  r.a = rd<u16>(b, o); r.x = rd<u16>(b, o); r.y = rd<u16>(b, o); r.sp = rd<u16>(b, o); r.d = rd<u16>(b, o);
  r.dbr = rd<u8>(b, o); r.k = rd<u8>(b, o); r.pc = rd<u16>(b, o); r.ps = rd<u8>(b, o); r.emu = rd<u8>(b, o);
  r.cycles = rd<uint64_t>(b, o);
  return r;
}

static bool is_replayed(u32 a) { return a == 0x2137 || a == 0x213D || a == 0x213F || a == 0x4210; }

static void build_map(std::vector<u32>& map, u32 romSize, u32 sramSize) {
  map.assign(4096, MK_OPEN << 28);
  u32 sramPages = sramSize / 0x1000;
  for (u32 bank = 0; bank < 256; bank++) {
    for (u32 p = 0; p < 16; p++) {
      u32 e = MK_OPEN << 28;
      u32 b7 = bank & 0x7F;
      if (bank < 0x40 || (bank >= 0x80 && bank < 0xC0)) {
        if (p < 2) e = (MK_WRAM << 28) | (p * 0x1000);
        else if (p < 6) e = MK_IO << 28;
        else if (p < 8) {
          if (b7 >= 0x20 && b7 < 0x40 && sramPages) e = (MK_SRAM << 28) | ((((b7 - 0x20) * 2 + (p - 6)) % sramPages) * 0x1000);
        } else e = (MK_ROM << 28) | (((b7 & 0x3F) * 0x10000 + p * 0x1000) % romSize);
      } else if (bank == 0x7E || bank == 0x7F) {
        e = (MK_WRAM << 28) | ((bank - 0x7E) * 0x10000 + p * 0x1000);
      } else if (bank >= 0x40 && bank < 0x7E) {
        e = (MK_ROM << 28) | (((bank - 0x40) * 0x10000 + p * 0x1000) % romSize);
      } else {  // C0-FF
        e = (MK_ROM << 28) | (((bank - 0xC0) * 0x10000 + p * 0x1000) % romSize);
      }
      map[(bank << 4) | p] = e;
    }
  }
}

static Capture load_capture(const std::string& dir, const std::string& romPath) {
  Capture c;
  auto ib = slurp(dir + "/gpu_init.bin");
  if (memcmp(&ib[0], "GPUI", 4)) { fprintf(stderr, "bad init blob\n"); exit(2); }
  size_t o = 4;
  u32 nregs = rd<u32>(ib, o), ns = rd<u32>(ib, o), nt = rd<u32>(ib, o);
  size_t r0 = o;
  c.init = rd_regs(ib, o);
  o = r0 + nregs;
  c.wram.assign(ib.begin() + o, ib.begin() + o + 0x20000); o += 0x20000;
  c.sram.assign(ib.begin() + o, ib.begin() + o + ns); o += ns;
  std::string text(ib.begin() + o, ib.begin() + o + nt);
  size_t p = 0;
  while (p < text.size()) {
    size_t nl = text.find('\n', p); if (nl == std::string::npos) nl = text.size();
    std::string line = text.substr(p, nl - p);
    size_t eq = line.find('=');
    if (eq != std::string::npos) c.kv[line.substr(0, eq)] = line.substr(eq + 1);
    p = nl + 1;
  }
  auto tb = slurp(dir + "/gpu_trace.bin");
  if (memcmp(&tb[0], "GPUT", 4)) { fprintf(stderr, "bad trace blob\n"); exit(2); }
  o = 4;
  u32 nev = rd<u32>(tb, o), npc = rd<u32>(tb, o);
  c.pc_frames = rd<u32>(tb, o);
  c.pcs.resize(npc);
  memcpy(c.pcs.data(), &tb[o], 4 * npc); o += 4 * npc;
  for (u32 i = 0; i < nev; i++) {
    char t = (char)tb[o];
    if (t == 'R' || t == 'W') {
      o++;
      IoEv e; e.tag = t; e.icount = rd<u32>(tb, o); e.addr = rd<u32>(tb, o); e.value = rd<u8>(tb, o);
      c.io.push_back(e);
    } else {
      o++;
      IntEv e; e.tag = t; e.icount = rd<u32>(tb, o); e.regs = rd_regs(tb, o);
      memcpy(e.hash, &tb[o], 512); o += 512;
      c.ints.push_back(e);
    }
  }
  if (o != tb.size()) { fprintf(stderr, "trace blob: %zu trailing bytes\n", tb.size() - o); exit(2); }
  c.rom = slurp(romPath);
  build_map(c.map, (u32)c.rom.size(), (u32)c.sram.size());
  for (auto& e : c.ints) {
    if (e.tag != 'N') { fprintf(stderr, "IRQ in trace: not modelled\n"); exit(2); }
    c.nmi_at.push_back(e.icount);
  }
  // per-frame pad word: the auto-joypad latch as the game read it
  size_t nframes = c.nmi_at.size() + 1;
  c.pad.assign(nframes, 0);
  std::vector<int> seen(nframes, 0);
  size_t f = 0;
  for (auto& e : c.io) {
    while (f < c.nmi_at.size() && c.nmi_at[f] < e.icount) f++;
    if (e.tag != 'R') continue;
    u32 a = e.addr & 0xFFFF;
    if (a == 0x4218 && !(seen[f] & 1)) { c.pad[f] = (c.pad[f] & 0xFF00) | e.value; seen[f] |= 1; }
    if (a == 0x4219 && !(seen[f] & 2)) { c.pad[f] = (c.pad[f] & 0x00FF) | (e.value << 8); seen[f] |= 2; }
    if (is_replayed(a)) { c.io_at.push_back(e.icount); c.io_val.push_back(a | ((u32)e.value << 16)); }
  }
  for (size_t i = 1; i < nframes; i++) if (!seen[i]) c.pad[i] = c.pad[i - 1];
  return c;
}

static Cpu initial_cpu(const Capture& c) {
  Cpu s; memset(&s, 0, sizeof s);
  s.a = c.init.a; s.x = c.init.x; s.y = c.init.y; s.sp = c.init.sp; s.d = c.init.d;
  s.dbr = c.init.dbr; s.k = c.init.k; s.pc = c.init.pc; s.p = c.init.ps; s.e = c.init.emu;
  auto num = [&](const char* k) -> u32 {
    auto it = c.kv.find(k);
    if (it == c.kv.end()) { fprintf(stderr, "missing state key %s\n", k); exit(2); }
    return (u32)strtoul(it->second.c_str(), nullptr, 10);
  };
  s.alu_m1 = num("internalRegisters.aluMulDiv.multOperand1");
  s.alu_dividend = num("internalRegisters.aluMulDiv.dividend");
  s.alu_divres = num("internalRegisters.aluMulDiv.divResult");
  s.alu_multrem = num("internalRegisters.aluMulDiv.multOrRemainderResult");
  s.wram_port = num("memoryManager.registerHandlerB.wramPosition");
  s.first_bad_frame = 0xFFFFFFFFu;
  return s;
}

static void wram_hashes(const u8* w, u32 stride, u32 out[128]) {
  for (u32 b = 0; b < 128; b++) {
    u32 h = 2166136261u;
    for (u32 o = 0; o < 1024; o += 4) {
      u32 i = b * 1024 + o;
      u32 word = w[i * stride] | (w[(i + 1) * stride] << 8) | (w[(i + 2) * stride] << 16) | ((u32)w[(i + 3) * stride] << 24);
      h = (h ^ word) * 16777619u;
    }
    out[b] = h;
  }
}

static bool regs_match(const Cpu& s, const Regs& r) {
  return s.a == r.a && s.x == r.x && s.y == r.y && s.sp == r.sp && s.d == r.d && s.dbr == r.dbr &&
         s.k == r.k && s.pc == r.pc && s.p == r.ps && s.e == r.emu;
}

static std::string fmt_cpu(const Cpu& s) {
  char b[160];
  snprintf(b, sizeof b, "A=%04X X=%04X Y=%04X S=%04X D=%04X DB=%02X PC=%02X:%04X P=%02X E=%u",
           s.a, s.x, s.y, s.sp, s.d, s.dbr, s.k, s.pc, s.p, s.e);
  return b;
}
static std::string fmt_regs(const Regs& r) {
  char b[160];
  snprintf(b, sizeof b, "A=%04X X=%04X Y=%04X S=%04X D=%04X DB=%02X PC=%02X:%04X P=%02X E=%u",
           r.a, r.x, r.y, r.sp, r.d, r.dbr, r.k, r.pc, r.ps, r.emu);
  return b;
}
