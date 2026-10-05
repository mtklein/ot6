// core.h -- a table-driven 65816 interpreter for the #392 GPU spike.
//
// One source, two compilers: included by the host (C++, the reference run
// that checks every frame's WRAM against Mesen) and by the Metal kernel
// (MSL is C++14-based).  The semantics are ported from Mesen 2.2.1's
// SnesCpu (Core/SNES/SnesCpu.Instructions.h, GPL-3.0 like OT6): the same
// flag rules, decimal-mode arithmetic, wrap masks and MVN/MVP stepping one
// byte per instruction, so instruction counts line up with Mesen's exec
// callbacks.  Cycle timing is NOT modelled: interrupts are replayed at the
// instruction counts Mesen recorded (see replay.h).
//
// Decode is a 256-entry table: each opcode is (addressing mode, operation,
// width class, load?, store?).  Execution is five fixed stages (operand
// address, load, ALU, store, control flow), each a switch over a small
// enum, so lanes of a SIMD group that run different opcodes of the same
// mode or operation class stay converged through most of an instruction.
#pragma once

#ifdef __METAL_VERSION__
#define DEV device
#define CDEV device const
#define THR thread
typedef uchar u8;
typedef ushort u16;
typedef uint u32;
typedef int i32;
#else
#include <stdint.h>
#define DEV
#define CDEV const
#define THR
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef int32_t i32;
#endif

// ---------------------------------------------------------------- flags --
#define F_C 0x01u
#define F_Z 0x02u
#define F_I 0x04u
#define F_D 0x08u
#define F_X 0x10u
#define F_M 0x20u
#define F_V 0x40u
#define F_N 0x80u

// ------------------------------------------------------- addressing modes --
enum {
  AM_IMP, AM_IMM8, AM_IMM16, AM_IMMM, AM_IMMX, AM_DIR, AM_DIRX, AM_DIRY,
  AM_DIRIND, AM_DIRXIND, AM_DIRINDY, AM_DIRINDL, AM_DIRINDLY, AM_ABS,
  AM_ABSX, AM_ABSY, AM_ABSL, AM_ABSLX, AM_SR, AM_SRINDY, AM_REL8, AM_REL16,
  AM_ABSJMP, AM_ABSLJMP, AM_ABSIND, AM_ABSINDL, AM_ABSXIND, AM_BLK, AM_NONE
};

// ------------------------------------------------------------ operations --
enum {
  OP_ORA, OP_AND, OP_EOR, OP_ADC, OP_SBC, OP_CMP, OP_CPX, OP_CPY, OP_BIT,
  OP_LDA, OP_LDX, OP_LDY, OP_STA, OP_STX, OP_STY, OP_STZ,
  OP_ASL, OP_LSR, OP_ROL, OP_ROR, OP_INC, OP_DEC, OP_TSB, OP_TRB,
  OP_ASLA, OP_LSRA, OP_ROLA, OP_RORA, OP_INA, OP_DEA,
  OP_INX, OP_INY, OP_DEX, OP_DEY,
  OP_BRANCH, OP_BRL, OP_JMP, OP_JML, OP_JSR, OP_JSL, OP_JSRXIND,
  OP_RTS, OP_RTL, OP_RTI, OP_BRK, OP_COP,
  OP_PHA, OP_PHX, OP_PHY, OP_PHP, OP_PHB, OP_PHD, OP_PHK,
  OP_PLA, OP_PLX, OP_PLY, OP_PLP, OP_PLB, OP_PLD, OP_PEA, OP_PEI, OP_PER,
  OP_CLC, OP_SEC, OP_CLI, OP_SEI, OP_CLD, OP_SED, OP_CLV, OP_REP, OP_SEP,
  OP_TAX, OP_TAY, OP_TXA, OP_TYA, OP_TXY, OP_TYX, OP_TSX, OP_TXS, OP_TCS,
  OP_TSC, OP_TCD, OP_TDC, OP_XBA, OP_XCE, OP_NOP, OP_WAI, OP_STP,
  OP_MVN, OP_MVP
};

// width classes: the operand width follows M, X, or is fixed.
enum { W_M = 0, W_X = 1, W_8 = 2, W_16 = 3 };

// decode word: mode (5 bits) | op << 5 (7 bits) | width << 12 | load << 14
//   | store << 15 | cond << 16 (branch condition, 3 bits) | write-idx << 19
#define DEC(mode, op, w, ld, st) ((u32)(mode) | ((u32)(op) << 5) | ((u32)(w) << 12) | ((u32)(ld) << 14) | ((u32)(st) << 15))
#define BR(cond) (DEC(AM_REL8, OP_BRANCH, W_8, 0, 0) | ((u32)(cond) << 16))

// --------------------------------------------------------- machine state --
struct Cpu {
  u32 a, x, y, sp, d, pc, dbr, k, p, e;
  u32 icount;      // instructions executed since the segment began
  u32 frame;       // NMIs taken since the segment began
  u32 nmi_idx;     // next entry of the interrupt schedule
  u32 io_idx;      // next entry of the replayed-read stream
  u32 alu_m1, alu_dividend, alu_divres, alu_multrem;
  u32 wram_port;   // $2181-$2183
  u32 status;      // 0 running; else an ST_* code
  u32 info;        // detail for status (an address, an opcode)
  u32 first_bad_frame;  // first frame whose registers differed from the trace (0xFFFFFFFF none)
  u32 pad0;
};

enum { ST_OK = 0, ST_DONE = 1, ST_STP = 2, ST_IO_READ = 3, ST_IO_MISMATCH = 4,
       ST_OPEN_BUS = 5, ST_WAI_HANG = 6, ST_IO_EXHAUSTED = 7 };

// memory map entry kinds (map[addr >> 12] = kind << 28 | base)
#define MK_WRAM 0u
#define MK_ROM 1u
#define MK_SRAM 2u
#define MK_IO 3u
#define MK_OPEN 4u

// Everything one instance touches.  wram/sram point at this instance's
// byte 0; byte i is at [i * stride]: stride 1 is instance-contiguous,
// stride B interleaves blocks of B instances byte by byte (the kernel sets
// the pointers; 64-bit there, 32-bit offsets here).
struct Ctx {
  DEV u8* wram;
  DEV u8* sram;
  CDEV u8* rom;
  CDEV u32* map;          // 4096 page entries
  CDEV u32* nmi_at;       // instruction counts at which NMIs are taken
  u32 n_nmi;
  CDEV u32* io_at;        // replayed reads: instruction count
  CDEV u32* io_val;       // replayed reads: addr16 | value << 16
  u32 n_io;
  CDEV u16* pad;          // per-frame joypad 1 word for this instance
  u32 stride;
  u32 sram_mask;
  u32 io_check;           // 1: check replayed-read addresses (and icounts)
};

// ------------------------------------------------------------- memory --
#define WR(c, i) (c).wram[(u32)(i) * (c).stride]
#define SR(c, i) (c).sram[(u32)(i) * (c).stride]

#ifndef IO_HOOK
#define IO_HOOK(s, addr, v) (v)
#endif
static inline u32 io_read_raw(THR Cpu& s, THR Ctx& c, u32 addr);
static inline u32 io_read(THR Cpu& s, THR Ctx& c, u32 addr) {
  return IO_HOOK(s, addr, io_read_raw(s, c, addr));
}
static inline u32 io_read_raw(THR Cpu& s, THR Ctx& c, u32 addr) {
  u32 a = addr & 0xFFFF;
  switch (a) {
    case 0x4214: return s.alu_divres & 0xFF;
    case 0x4215: return (s.alu_divres >> 8) & 0xFF;
    case 0x4216: return s.alu_multrem & 0xFF;
    case 0x4217: return (s.alu_multrem >> 8) & 0xFF;
    case 0x4218: return c.pad[s.frame] & 0xFF;
    case 0x4219: return (c.pad[s.frame] >> 8) & 0xFF;
    case 0x421A: case 0x421B: case 0x421C: case 0x421D: case 0x421E: case 0x421F: return 0;
    case 0x2180: { u32 v = WR(c, s.wram_port); s.wram_port = (s.wram_port + 1) & 0x1FFFF; return v; }
    case 0x2137: case 0x213D: case 0x213F: case 0x4210: {
      // PPU/timing status: replayed from Mesen's trace, in order.
      if (s.io_idx >= c.n_io) { s.status = ST_IO_EXHAUSTED; s.info = a; return 0; }
      u32 v = c.io_val[s.io_idx];
      if (c.io_check && ((v & 0xFFFF) != a || c.io_at[s.io_idx] != s.icount + 1)) {
        s.status = ST_IO_MISMATCH; s.info = a | (s.io_idx << 16);
      }
      s.io_idx++;
      return (v >> 16) & 0xFF;
    }
    default:
      s.status = ST_IO_READ; s.info = addr;
      return 0;
  }
}

static inline void io_write(THR Cpu& s, THR Ctx& c, u32 addr, u32 v) {
  u32 a = addr & 0xFFFF;
  switch (a) {
    case 0x4202: s.alu_m1 = v; break;
    case 0x4203: s.alu_multrem = s.alu_m1 * v; s.alu_divres = v;
#ifdef MUT_ALU
      if (s.frame >= 300) s.alu_multrem ^= 1;  // negative control: product off by one bit
#endif
      break;
    case 0x4204: s.alu_dividend = (s.alu_dividend & 0xFF00) | v; break;
    case 0x4205: s.alu_dividend = (s.alu_dividend & 0x00FF) | (v << 8); break;
    case 0x4206:
      if (v == 0) { s.alu_divres = 0xFFFF; s.alu_multrem = s.alu_dividend; }
      else { s.alu_divres = s.alu_dividend / v; s.alu_multrem = s.alu_dividend % v; }
      break;
    case 0x2180: WR(c, s.wram_port) = (u8)v; s.wram_port = (s.wram_port + 1) & 0x1FFFF; break;
    case 0x2181: s.wram_port = (s.wram_port & 0x1FF00) | v; break;
    case 0x2182: s.wram_port = (s.wram_port & 0x100FF) | (v << 8); break;
    case 0x2183: s.wram_port = (s.wram_port & 0x0FFFF) | ((v & 1) << 16); break;
    default: break;  // PPU, APU ports, DMA/HDMA: no effect on WRAM (measured)
  }
}

static inline u32 rd8(THR Cpu& s, THR Ctx& c, u32 addr) {
  u32 m = c.map[(addr >> 12) & 0xFFF];
  u32 off = (m & 0x0FFFFFFF) + (addr & 0xFFF);
  switch (m >> 28) {
    case MK_WRAM: return WR(c, off);
    case MK_ROM: return c.rom[off];
    case MK_SRAM: return SR(c, off & c.sram_mask);
    case MK_IO: return io_read(s, c, addr);
    default: s.status = ST_OPEN_BUS; s.info = addr; return 0;
  }
}

static inline void wr8(THR Cpu& s, THR Ctx& c, u32 addr, u32 v) {
  u32 m = c.map[(addr >> 12) & 0xFFF];
  u32 off = (m & 0x0FFFFFFF) + (addr & 0xFFF);
  switch (m >> 28) {
    case MK_WRAM: WR(c, off) = (u8)v; break;
    case MK_SRAM: SR(c, off & c.sram_mask) = (u8)v; break;
    case MK_IO: io_write(s, c, addr, v & 0xFF); break;
    default: break;  // ROM and open bus ignore writes
  }
}

// ---------------------------------------------------------------- stack --
static inline void push8(THR Cpu& s, THR Ctx& c, u32 v, bool allowEmu) {
  wr8(s, c, s.sp, v);
  u32 sp = (s.sp - 1) & 0xFFFF;
  s.sp = (allowEmu && s.e) ? (0x100 | (sp & 0xFF)) : sp;
}
static inline u32 pop8(THR Cpu& s, THR Ctx& c, bool allowEmu) {
  u32 sp = (s.sp + 1) & 0xFFFF;
  s.sp = (allowEmu && s.e) ? (0x100 | (sp & 0xFF)) : sp;
  return rd8(s, c, s.sp);
}
static inline void push16(THR Cpu& s, THR Ctx& c, u32 v, bool allowEmu) {
  push8(s, c, (v >> 8) & 0xFF, allowEmu);
  push8(s, c, v & 0xFF, allowEmu);
}
static inline u32 pop16(THR Cpu& s, THR Ctx& c, bool allowEmu) {
  u32 lo = pop8(s, c, allowEmu);
  u32 hi = pop8(s, c, allowEmu);
  return lo | (hi << 8);
}
static inline void restrict_sp(THR Cpu& s) { if (s.e) s.sp = 0x100 | (s.sp & 0xFF); }

static inline void set_p(THR Cpu& s, u32 p) {
  s.p = p & 0xFF;
  if (s.p & F_X) { s.x &= 0xFF; s.y &= 0xFF; }
}

static inline void nz8(THR Cpu& s, u32 v) {
  s.p = (s.p & ~(F_N | F_Z)) | ((v & 0xFF) == 0 ? F_Z : 0u) | (v & 0x80);
}
static inline void nz16(THR Cpu& s, u32 v) {
  s.p = (s.p & ~(F_N | F_Z)) | ((v & 0xFFFF) == 0 ? F_Z : 0u) | ((v >> 8) & 0x80);
}
static inline void nzw(THR Cpu& s, u32 v, bool w8) { if (w8) nz8(s, v); else nz16(s, v); }

// set a register at width: 8-bit keeps the high byte
static inline u32 setw(THR Cpu& s, u32 reg, u32 v, bool w8) {
  nzw(s, v, w8);
  return w8 ? ((reg & 0xFF00) | (v & 0xFF)) : (v & 0xFFFF);
}

static inline u32 fetch8(THR Cpu& s, THR Ctx& c) {
  u32 v = rd8(s, c, (s.k << 16) | s.pc);
  s.pc = (s.pc + 1) & 0xFFFF;
  return v;
}
static inline u32 fetch16(THR Cpu& s, THR Ctx& c) {
  u32 lo = fetch8(s, c);
  return lo | (fetch8(s, c) << 8);
}

static inline u32 dp_addr(THR Cpu& s, u32 off, bool allowEmu) {
  if (allowEmu && s.e && (s.d & 0xFF) == 0) return (s.d & 0xFF00) | (off & 0xFF);
  return (s.d + off) & 0xFFFF;
}

// ---------------------------------------------------------------- ALU --
static inline u32 adc(THR Cpu& s, u32 value, bool w8) {
  u32 A = s.a;
  u32 result;
  bool dec = (s.p & F_D) != 0;
  u32 cin = s.p & F_C;
  if (w8) {
    if (dec) {
      result = (A & 0x0F) + (value & 0x0F) + cin;
      if (result > 0x09) result += 0x06;
      result = (A & 0xF0) + (value & 0xF0) + (result > 0x0F ? 0x10u : 0u) + (result & 0x0F);
    } else {
      result = (A & 0xFF) + value + cin;
    }
    u32 v = (~(A ^ value) & (A ^ result) & 0x80) ? F_V : 0u;
    if (dec && result > 0x9F) result += 0x60;
    s.p = (s.p & ~(F_C | F_N | F_Z | F_V)) | v | ((result & 0xFF) == 0 ? F_Z : 0u) | (result & 0x80) | (result > 0xFF ? F_C : 0u);
    return (A & 0xFF00) | (result & 0xFF);
  } else {
    if (dec) {
      result = (A & 0x0F) + (value & 0x0F) + cin;
      if (result > 0x09) result += 0x06;
      result = (A & 0xF0) + (value & 0xF0) + (result > 0x0F ? 0x10u : 0u) + (result & 0x0F);
      if (result > 0x9F) result += 0x60;
      result = (A & 0xF00) + (value & 0xF00) + (result > 0xFF ? 0x100u : 0u) + (result & 0xFF);
      if (result > 0x9FF) result += 0x600;
      result = (A & 0xF000) + (value & 0xF000) + (result > 0xFFF ? 0x1000u : 0u) + (result & 0xFFF);
    } else {
      result = A + value + cin;
    }
    u32 v = (~(A ^ value) & (A ^ result) & 0x8000) ? F_V : 0u;
    if (dec && result > 0x9FFF) result += 0x6000;
    s.p = (s.p & ~(F_C | F_N | F_Z | F_V)) | v | ((result & 0xFFFF) == 0 ? F_Z : 0u) | ((result >> 8) & 0x80) | (result > 0xFFFF ? F_C : 0u);
    return result & 0xFFFF;
  }
}

// SBC is Mesen's Sub8/Sub16 with value already complemented
static inline u32 sbc(THR Cpu& s, u32 value, bool w8) {
  i32 A = (i32)s.a;
  i32 val = (i32)value;
  i32 result;
  bool dec = (s.p & F_D) != 0;
  i32 cin = (i32)(s.p & F_C);
  if (w8) {
    if (dec) {
      result = (A & 0x0F) + (val & 0x0F) + cin;
      if (result <= 0x0F) result -= 0x06;
      result = (A & 0xF0) + (val & 0xF0) + (result > 0x0F ? 0x10 : 0) + (result & 0x0F);
    } else {
      result = (A & 0xFF) + val + cin;
    }
    u32 v = (~(A ^ val) & (A ^ result) & 0x80) ? F_V : 0u;
    if (dec && result <= 0xFF) result -= 0x60;
    s.p = (s.p & ~(F_C | F_N | F_Z | F_V)) | v | ((result & 0xFF) == 0 ? F_Z : 0u) | ((u32)result & 0x80) | (result > 0xFF ? F_C : 0u);
    return ((u32)A & 0xFF00) | ((u32)result & 0xFF);
  } else {
    if (dec) {
      result = (A & 0x0F) + (val & 0x0F) + cin;
      if (result <= 0x0F) result -= 0x06;
      result = (A & 0xF0) + (val & 0xF0) + (result > 0x0F ? 0x10 : 0) + (result & 0x0F);
      if (result <= 0xFF) result -= 0x60;
      result = (A & 0xF00) + (val & 0xF00) + (result > 0xFF ? 0x100 : 0) + (result & 0xFF);
      if (result <= 0xFFF) result -= 0x600;
      result = (A & 0xF000) + (val & 0xF000) + (result > 0xFFF ? 0x1000 : 0) + (result & 0xFFF);
    } else {
      result = A + val + cin;
    }
    u32 v = (~(A ^ val) & (A ^ result) & 0x8000) ? F_V : 0u;
    if (dec && result <= 0xFFFF) result -= 0x6000;
    s.p = (s.p & ~(F_C | F_N | F_Z | F_V)) | v | ((result & 0xFFFF) == 0 ? F_Z : 0u) | (((u32)result >> 8) & 0x80) | (result > 0xFFFF ? F_C : 0u);
    return (u32)result & 0xFFFF;
  }
}

static inline void compare(THR Cpu& s, u32 reg, u32 value, bool w8) {
  u32 mask = w8 ? 0xFFu : 0xFFFFu;
  u32 r = reg & mask;
  s.p = (s.p & ~F_C) | (r >= value ? F_C : 0u);
  nzw(s, (r - value) & mask, w8);
}

// ---------------------------------------------------------- interrupts --
static inline void interrupt(THR Cpu& s, THR Ctx& c, u32 vector) {
  if (s.e) {
    push16(s, c, s.pc, true);
    push8(s, c, s.p | 0x20, true);
  } else {
    push8(s, c, s.k, true);
    push16(s, c, s.pc, true);
    push8(s, c, s.p, true);
  }
  s.p = (s.p | F_I) & ~F_D;
  s.k = 0;
  u32 lo = rd8(s, c, vector);
  s.pc = lo | (rd8(s, c, vector + 1) << 8);
}

// ---------------------------------------------------------- one opcode --
static inline void step(THR Cpu& s, THR Ctx& c, CDEV u32* dectab) {
  u32 opcode = fetch8(s, c);
  u32 dw = dectab[opcode];
  u32 mode = dw & 31, op = (dw >> 5) & 127, wcls = (dw >> 12) & 3;
  bool load = (dw >> 14) & 1, store = (dw >> 15) & 1;
  bool w8 = wcls == W_8 || (wcls == W_M && (s.p & F_M)) || (wcls == W_X && (s.p & F_X));
  u32 mask = 0xFFFFFFu;  // Mesen's _readWriteMask
  u32 ea = 0;
  bool imm = false;

  // ---- stage 1: operand address
  switch (mode) {
    case AM_IMP: break;
    case AM_IMM8: imm = true; ea = fetch8(s, c); break;
    case AM_IMM16: imm = true; ea = fetch16(s, c); break;
    case AM_IMMM: imm = true; ea = (s.p & F_M) ? fetch8(s, c) : fetch16(s, c); break;
    case AM_IMMX: imm = true; ea = (s.p & F_X) ? fetch8(s, c) : fetch16(s, c); break;
    case AM_DIR: mask = 0xFFFF; ea = dp_addr(s, fetch8(s, c), true); break;
    case AM_DIRX: mask = 0xFFFF; ea = dp_addr(s, (fetch8(s, c) + s.x) & 0xFFFF, true); break;
    case AM_DIRY: mask = 0xFFFF; ea = dp_addr(s, (fetch8(s, c) + s.y) & 0xFFFF, true); break;
    case AM_DIRIND: {
      u32 o = fetch8(s, c);
      u32 lo = rd8(s, c, dp_addr(s, o, true));
      u32 hi = rd8(s, c, dp_addr(s, (o + 1) & 0xFFFF, true));
      ea = (s.dbr << 16) | lo | (hi << 8);
      break;
    }
    case AM_DIRXIND: {
      u32 o = (fetch8(s, c) + s.x) & 0xFFFF;
      u32 lo = rd8(s, c, dp_addr(s, o, true));
      u32 hi;
      if (!s.e || (s.d & 0xFF) == 0) {
        hi = rd8(s, c, dp_addr(s, (o + 1) & 0xFFFF, true));
      } else {
        u32 a2 = dp_addr(s, (o + 1) & 0xFFFF, true);
        hi = rd8(s, c, (a2 & 0xFF) == 0 ? ((a2 - 0x100) & 0xFFFF) : a2);
      }
      ea = (s.dbr << 16) | lo | (hi << 8);
      break;
    }
    case AM_DIRINDY: {
      u32 o = fetch8(s, c);
      u32 lo = rd8(s, c, dp_addr(s, o, true));
      u32 hi = rd8(s, c, dp_addr(s, (o + 1) & 0xFFFF, true));
      ea = (((s.dbr << 16) | lo | (hi << 8)) + s.y) & 0xFFFFFF;
      break;
    }
    case AM_DIRINDL: case AM_DIRINDLY: {
      u32 o = fetch8(s, c);
      u32 b1 = rd8(s, c, dp_addr(s, o, false));
      u32 b2 = rd8(s, c, dp_addr(s, (o + 1) & 0xFFFF, false));
      u32 b3 = rd8(s, c, dp_addr(s, (o + 2) & 0xFFFF, false));
      ea = b1 | (b2 << 8) | (b3 << 16);
      if (mode == AM_DIRINDLY) ea = (ea + s.y) & 0xFFFFFF;
      break;
    }
    case AM_ABS: ea = (s.dbr << 16) | fetch16(s, c); break;
    case AM_ABSX: ea = (((s.dbr << 16) | fetch16(s, c)) + s.x) & 0xFFFFFF; break;
    case AM_ABSY: ea = (((s.dbr << 16) | fetch16(s, c)) + s.y) & 0xFFFFFF; break;
    case AM_ABSL: { u32 lo = fetch16(s, c); ea = lo | (fetch8(s, c) << 16); break; }
    case AM_ABSLX: { u32 lo = fetch16(s, c); ea = ((lo | (fetch8(s, c) << 16)) + s.x) & 0xFFFFFF; break; }
    case AM_SR: ea = (fetch8(s, c) + s.sp) & 0xFFFF; break;
    case AM_SRINDY: {
      u32 a0 = (fetch8(s, c) + s.sp) & 0xFFFF;
      u32 lo = rd8(s, c, a0);
      u32 hi = rd8(s, c, (a0 + 1) & 0xFFFF);
      ea = (((s.dbr << 16) | lo | (hi << 8)) + s.y) & 0xFFFFFF;
      break;
    }
    case AM_REL8: ea = fetch8(s, c); break;
    case AM_REL16: ea = fetch16(s, c); break;
    case AM_ABSJMP: ea = fetch16(s, c); break;
    case AM_ABSLJMP: { u32 lo = fetch16(s, c); ea = lo | (fetch8(s, c) << 16); break; }
    case AM_ABSIND: {
      u32 a0 = fetch16(s, c);
      u32 lo = rd8(s, c, a0);
      ea = lo | (rd8(s, c, (a0 + 1) & 0xFFFF) << 8);
      break;
    }
    case AM_ABSINDL: {
      u32 a0 = fetch16(s, c);
      u32 b1 = rd8(s, c, a0);
      u32 b2 = rd8(s, c, (a0 + 1) & 0xFFFF);
      ea = b1 | (b2 << 8) | (rd8(s, c, (a0 + 2) & 0xFFFF) << 16);
      break;
    }
    case AM_ABSXIND: {
      u32 a0 = (fetch16(s, c) + s.x) & 0xFFFF;
      u32 lo = rd8(s, c, (s.k << 16) | a0);
      ea = lo | (rd8(s, c, (s.k << 16) | ((a0 + 1) & 0xFFFF)) << 8);
      break;
    }
    case AM_BLK: ea = fetch16(s, c); break;
    default: break;
  }

  // ---- stage 2: load
  u32 val = 0;
  if (load) {
    if (imm) val = ea;
    else {
      val = rd8(s, c, ea);
      if (!w8) val |= rd8(s, c, (ea + 1) & mask) << 8;
    }
  }

  // ---- stage 3: operation
  u32 res = 0;
  switch (op) {
    case OP_ORA: s.a = setw(s, s.a, s.a | val, w8); break;
    case OP_AND: s.a = setw(s, s.a, s.a & val, w8); break;
    case OP_EOR: s.a = setw(s, s.a, s.a ^ val, w8); break;
    case OP_ADC: s.a = adc(s, val, w8); break;
    case OP_SBC: s.a = sbc(s, (~val) & (w8 ? 0xFFu : 0xFFFFu), w8); break;
    case OP_CMP: compare(s, s.a, val, w8); break;
    case OP_CPX: compare(s, s.x, val, w8); break;
    case OP_CPY: compare(s, s.y, val, w8); break;
    case OP_BIT: {
      u32 m = w8 ? 0xFFu : 0xFFFFu;
      u32 z = ((s.a & val & m) == 0) ? F_Z : 0u;
      if (imm) s.p = (s.p & ~F_Z) | z;
      else {
        u32 top = w8 ? val : (val >> 8);
        s.p = (s.p & ~(F_Z | F_V | F_N)) | z | (top & 0xC0);
      }
      break;
    }
    case OP_LDA: s.a = setw(s, s.a, val, w8); break;
    case OP_LDX: s.x = setw(s, s.x, val, w8); break;
    case OP_LDY: s.y = setw(s, s.y, val, w8); break;
    case OP_STA: res = s.a; break;
    case OP_STX: res = s.x; break;
    case OP_STY: res = s.y; break;
    case OP_STZ: res = 0; break;
    case OP_ASL: case OP_ASLA: {
      u32 v = op == OP_ASLA ? s.a : val;
      u32 top = w8 ? 0x80u : 0x8000u;
      u32 r = (v << 1) & (w8 ? 0xFFu : 0xFFFFu);
      s.p = (s.p & ~F_C) | ((v & top) ? F_C : 0u);
      nzw(s, r, w8);
      if (op == OP_ASLA) s.a = w8 ? ((s.a & 0xFF00) | r) : r; else res = r;
      break;
    }
    case OP_LSR: case OP_LSRA: {
      u32 v = (op == OP_LSRA ? s.a : val) & (w8 ? 0xFFu : 0xFFFFu);
      u32 r = v >> 1;
      s.p = (s.p & ~F_C) | (v & 1);
      nzw(s, r, w8);
      if (op == OP_LSRA) s.a = w8 ? ((s.a & 0xFF00) | r) : r; else res = r;
      break;
    }
    case OP_ROL: case OP_ROLA: {
      u32 v = op == OP_ROLA ? s.a : val;
      u32 top = w8 ? 0x80u : 0x8000u;
      u32 r = ((v << 1) | (s.p & F_C)) & (w8 ? 0xFFu : 0xFFFFu);
      s.p = (s.p & ~F_C) | ((v & top) ? F_C : 0u);
      nzw(s, r, w8);
      if (op == OP_ROLA) s.a = w8 ? ((s.a & 0xFF00) | r) : r; else res = r;
      break;
    }
    case OP_ROR: case OP_RORA: {
      u32 v = (op == OP_RORA ? s.a : val) & (w8 ? 0xFFu : 0xFFFFu);
      u32 r = (v >> 1) | ((s.p & F_C) << (w8 ? 7 : 15));
      s.p = (s.p & ~F_C) | (v & 1);
      nzw(s, r, w8);
      if (op == OP_RORA) s.a = w8 ? ((s.a & 0xFF00) | r) : r; else res = r;
      break;
    }
    case OP_INC: res = (val + 1) & (w8 ? 0xFFu : 0xFFFFu); nzw(s, res, w8); break;
    case OP_DEC: res = (val - 1) & (w8 ? 0xFFu : 0xFFFFu); nzw(s, res, w8); break;
    case OP_TSB: case OP_TRB: {
      u32 m = w8 ? 0xFFu : 0xFFFFu;
      s.p = (s.p & ~F_Z) | (((s.a & val & m) == 0) ? F_Z : 0u);
      res = op == OP_TSB ? ((val | s.a) & m) : (val & ~s.a & m);
      break;
    }
    case OP_INA: s.a = setw(s, s.a, s.a + 1, w8); break;
    case OP_DEA: s.a = setw(s, s.a, s.a - 1, w8); break;
    case OP_INX: s.x = setw(s, s.x, s.x + 1, w8); break;
    case OP_INY: s.y = setw(s, s.y, s.y + 1, w8); break;
    case OP_DEX: s.x = setw(s, s.x, s.x - 1, w8); break;
    case OP_DEY: s.y = setw(s, s.y, s.y - 1, w8); break;
    case OP_BRANCH: {
      u32 cond = (dw >> 16) & 7;
      bool take;
      switch (cond) {
        case 0: take = !(s.p & F_N); break;   // BPL
        case 1: take = (s.p & F_N) != 0; break;  // BMI
        case 2: take = !(s.p & F_V); break;   // BVC
        case 3: take = (s.p & F_V) != 0; break;  // BVS
        case 4: take = !(s.p & F_C); break;   // BCC
        case 5: take = (s.p & F_C) != 0; break;  // BCS
        case 6: take = !(s.p & F_Z); break;   // BNE
        case 7: take = (s.p & F_Z) != 0; break;  // BEQ
        default: take = true; break;
      }
      if (opcode == 0x80) take = true;  // BRA
      if (take) s.pc = (s.pc + ((ea & 0xFF) ^ 0x80u) - 0x80u) & 0xFFFF;
      break;
    }
    case OP_BRL: s.pc = (s.pc + ea) & 0xFFFF; break;
    case OP_JMP: s.pc = ea & 0xFFFF; break;
    case OP_JML: s.k = (ea >> 16) & 0xFF; s.pc = ea & 0xFFFF; break;
    case OP_JSR: push16(s, c, (s.pc - 1) & 0xFFFF, true); s.pc = ea & 0xFFFF; break;
    case OP_JSL: {
      // operand bytes are read around the push, as on hardware
      u32 b1 = fetch8(s, c), b2 = fetch8(s, c);
      push8(s, c, s.k, false);
      u32 b3 = fetch8(s, c);
      push16(s, c, (s.pc - 1) & 0xFFFF, false);
      s.k = b3; s.pc = b1 | (b2 << 8);
      restrict_sp(s);
      break;
    }
    case OP_JSRXIND: {
      u32 lo = fetch8(s, c);
      push16(s, c, s.pc, false);
      u32 hi = fetch8(s, c);
      u32 base = ((lo | (hi << 8)) + s.x) & 0xFFFF;
      u32 l2 = rd8(s, c, (s.k << 16) | base);
      u32 h2 = rd8(s, c, (s.k << 16) | ((base + 1) & 0xFFFF));
      s.pc = l2 | (h2 << 8);
      restrict_sp(s);
      break;
    }
    case OP_RTS: s.pc = (pop16(s, c, true) + 1) & 0xFFFF; break;
    case OP_RTL: s.pc = (pop16(s, c, false) + 1) & 0xFFFF; s.k = pop8(s, c, false); restrict_sp(s); break;
    case OP_RTI:
      if (s.e) { set_p(s, pop8(s, c, true) | F_M | F_X); s.pc = pop16(s, c, true); }
      else { set_p(s, pop8(s, c, true)); s.pc = pop16(s, c, true); s.k = pop8(s, c, true); }
      break;
    case OP_BRK: interrupt(s, c, s.e ? 0xFFFEu : 0xFFE6u); break;
    case OP_COP: interrupt(s, c, s.e ? 0xFFF4u : 0xFFE4u); break;
    case OP_PHA: if (w8) push8(s, c, s.a & 0xFF, true); else push16(s, c, s.a, true); break;
    case OP_PHX: if (w8) push8(s, c, s.x & 0xFF, true); else push16(s, c, s.x, true); break;
    case OP_PHY: if (w8) push8(s, c, s.y & 0xFF, true); else push16(s, c, s.y, true); break;
    case OP_PHP: push8(s, c, s.p, true); break;
    case OP_PHB: push8(s, c, s.dbr, true); break;
    case OP_PHK: push8(s, c, s.k, true); break;
    case OP_PHD: push16(s, c, s.d, false); restrict_sp(s); break;
    case OP_PEA: push16(s, c, ea, false); restrict_sp(s); break;
    case OP_PEI: {
      u32 lo = rd8(s, c, ea);
      u32 hi = rd8(s, c, (ea + 1) & 0xFFFF);
      push16(s, c, lo | (hi << 8), false);
      restrict_sp(s);
      break;
    }
    case OP_PER: push16(s, c, (ea + s.pc) & 0xFFFF, false); restrict_sp(s); break;
    case OP_PLA: s.a = setw(s, s.a, w8 ? pop8(s, c, true) : pop16(s, c, true), w8); break;
    case OP_PLX: s.x = setw(s, s.x, w8 ? pop8(s, c, true) : pop16(s, c, true), w8); break;
    case OP_PLY: s.y = setw(s, s.y, w8 ? pop8(s, c, true) : pop16(s, c, true), w8); break;
    case OP_PLP: set_p(s, s.e ? (pop8(s, c, true) | F_M | F_X) : pop8(s, c, true)); break;
    case OP_PLB: { u32 v = pop8(s, c, false); nz8(s, v); s.dbr = v; restrict_sp(s); break; }
    case OP_PLD: { u32 v = pop16(s, c, false); nz16(s, v); s.d = v; restrict_sp(s); break; }
    case OP_CLC: s.p &= ~F_C; break;
    case OP_SEC: s.p |= F_C; break;
    case OP_CLI: s.p &= ~F_I; break;
    case OP_SEI: s.p |= F_I; break;
    case OP_CLD: s.p &= ~F_D; break;
    case OP_SED: s.p |= F_D; break;
    case OP_CLV: s.p &= ~F_V; break;
    case OP_REP: s.p &= ~ea; if (s.e) s.p |= F_M | F_X; break;
    case OP_SEP: s.p |= ea & 0xFF; if (s.p & F_X) { s.x &= 0xFF; s.y &= 0xFF; } break;
    case OP_TAX: s.x = setw(s, s.x, s.a, w8); break;
    case OP_TAY: s.y = setw(s, s.y, s.a, w8); break;
    case OP_TXA: s.a = setw(s, s.a, s.x, w8); break;
    case OP_TYA: s.a = setw(s, s.a, s.y, w8); break;
    case OP_TXY: s.y = setw(s, s.y, s.x, w8); break;
    case OP_TYX: s.x = setw(s, s.x, s.y, w8); break;
    case OP_TSX: s.x = setw(s, s.x, s.sp, w8); break;
    case OP_TXS: s.sp = s.e ? (0x100 | (s.x & 0xFF)) : s.x; break;
    case OP_TCS: s.sp = s.e ? (0x100 | (s.a & 0xFF)) : s.a; break;
    case OP_TSC: s.a = s.sp; nz16(s, s.a); break;
    case OP_TCD: s.d = s.a; nz16(s, s.d); break;
    case OP_TDC: s.a = s.d; nz16(s, s.a); break;
    case OP_XBA: s.a = ((s.a & 0xFF) << 8) | ((s.a >> 8) & 0xFF); nz8(s, s.a); break;
    case OP_XCE: {
      u32 cflag = s.p & F_C;
      s.p = (s.p & ~F_C) | (s.e ? F_C : 0u);
      s.e = cflag;
      if (s.e) { set_p(s, s.p | F_M | F_X); s.sp = 0x100 | (s.sp & 0xFF); }
      break;
    }
    case OP_NOP: break;
    case OP_WAI:
      // The CPU sleeps until the next interrupt.  The schedule says when;
      // if the next NMI is not due right after this instruction, the
      // replay cannot know when to wake, so stop.
      if (s.nmi_idx >= c.n_nmi || c.nmi_at[s.nmi_idx] != s.icount + 1) { s.status = ST_WAI_HANG; s.info = s.icount; }
      break;
    case OP_STP: s.status = ST_STP; s.info = (s.k << 16) | s.pc; break;
    case OP_MVN: case OP_MVP: {
      s.dbr = ea & 0xFF;
      u32 dst = s.dbr << 16, src = (ea << 8) & 0xFF0000;
      u32 v = rd8(s, c, src | s.x);
      wr8(s, c, dst | s.y, v);
      u32 inc = op == OP_MVN ? 1u : 0xFFFFu;
      s.x = (s.x + inc) & 0xFFFF;
      s.y = (s.y + inc) & 0xFFFF;
      if (s.p & F_X) { s.x &= 0xFF; s.y &= 0xFF; }
      s.a = (s.a - 1) & 0xFFFF;
      if (s.a != 0xFFFF) s.pc = (s.pc - 3) & 0xFFFF;
      break;
    }
    default: break;
  }

  // ---- stage 4: store (read-modify-write writes the high byte first)
  if (store) {
    bool rmw = load;
    if (w8) wr8(s, c, ea, res & 0xFF);
    else if (rmw) { wr8(s, c, (ea + 1) & mask, (res >> 8) & 0xFF); wr8(s, c, ea, res & 0xFF); }
    else { wr8(s, c, ea, res & 0xFF); wr8(s, c, (ea + 1) & mask, (res >> 8) & 0xFF); }
  }

  s.icount++;
}

// After each instruction: take the NMI the schedule says follows it.
// Returns true when an NMI was taken (the caller checks the frame).
static inline bool maybe_nmi(THR Cpu& s, THR Ctx& c) {
  if (s.nmi_idx < c.n_nmi && c.nmi_at[s.nmi_idx] == s.icount) {
    interrupt(s, c, s.e ? 0xFFFAu : 0xFFEAu);
    s.nmi_idx++;
    s.frame++;
    return true;
  }
  return false;
}

// --------------------------------------------------------- decode table --
#ifndef __METAL_VERSION__
static void build_decode(u32* t) {
  // ALU group: ORA AND EOR ADC STA LDA CMP SBC share the classic 65xx grid
  const u32 grp[8] = { OP_ORA, OP_AND, OP_EOR, OP_ADC, OP_STA, OP_LDA, OP_CMP, OP_SBC };
  const u32 col[16] = { 0xFF, AM_DIRXIND, 0xFF, AM_SR, 0xFF, AM_DIR, 0xFF, AM_DIRINDL,
                        0xFF, AM_IMMM, 0xFF, 0xFF, 0xFF, AM_ABS, 0xFF, AM_ABSL };
  const u32 col2[16] = { 0xFF, AM_DIRINDY, AM_DIRIND, AM_SRINDY, 0xFF, AM_DIRX, 0xFF, AM_DIRINDLY,
                         0xFF, AM_ABSY, 0xFF, 0xFF, 0xFF, AM_ABSX, 0xFF, AM_ABSLX };
  for (int i = 0; i < 256; i++) t[i] = DEC(AM_NONE, OP_STP, W_8, 0, 0) | (1u << 31);
  for (u32 g = 0; g < 8; g++) {
    for (u32 lo = 0; lo < 16; lo++) {
      for (u32 h = 0; h < 2; h++) {
        u32 m = h ? col2[lo] : col[lo];
        if (m == 0xFF) continue;
        u32 opc = (g << 5) | (h << 4) | lo;
        if (grp[g] == OP_STA && m == AM_IMMM) continue;  // $89 is BIT #
        bool st = grp[g] == OP_STA;
        t[opc] = DEC(m, grp[g], W_M, !st, st);
      }
    }
  }
  // RMW memory ops (ASL ROL LSR ROR / DEC INC): dir, abs, dir,x, abs,x
  const u32 rmw[8] = { OP_ASL, OP_ROL, OP_LSR, OP_ROR, 0xFF, 0xFF, OP_DEC, OP_INC };
  for (u32 g = 0; g < 8; g++) {
    if (rmw[g] == 0xFF) continue;
    t[(g << 5) | 0x06] = DEC(AM_DIR, rmw[g], W_M, 1, 1);
    t[(g << 5) | 0x0E] = DEC(AM_ABS, rmw[g], W_M, 1, 1);
    t[(g << 5) | 0x16] = DEC(AM_DIRX, rmw[g], W_M, 1, 1);
    t[(g << 5) | 0x1E] = DEC(AM_ABSX, rmw[g], W_M, 1, 1);
  }
  t[0x0A] = DEC(AM_IMP, OP_ASLA, W_M, 0, 0); t[0x2A] = DEC(AM_IMP, OP_ROLA, W_M, 0, 0);
  t[0x4A] = DEC(AM_IMP, OP_LSRA, W_M, 0, 0); t[0x6A] = DEC(AM_IMP, OP_RORA, W_M, 0, 0);
  t[0x1A] = DEC(AM_IMP, OP_INA, W_M, 0, 0); t[0x3A] = DEC(AM_IMP, OP_DEA, W_M, 0, 0);
  t[0x04] = DEC(AM_DIR, OP_TSB, W_M, 1, 1); t[0x0C] = DEC(AM_ABS, OP_TSB, W_M, 1, 1);
  t[0x14] = DEC(AM_DIR, OP_TRB, W_M, 1, 1); t[0x1C] = DEC(AM_ABS, OP_TRB, W_M, 1, 1);
  t[0x24] = DEC(AM_DIR, OP_BIT, W_M, 1, 0); t[0x2C] = DEC(AM_ABS, OP_BIT, W_M, 1, 0);
  t[0x34] = DEC(AM_DIRX, OP_BIT, W_M, 1, 0); t[0x3C] = DEC(AM_ABSX, OP_BIT, W_M, 1, 0);
  t[0x89] = DEC(AM_IMMM, OP_BIT, W_M, 1, 0);
  // STZ
  t[0x64] = DEC(AM_DIR, OP_STZ, W_M, 0, 1); t[0x74] = DEC(AM_DIRX, OP_STZ, W_M, 0, 1);
  t[0x9C] = DEC(AM_ABS, OP_STZ, W_M, 0, 1); t[0x9E] = DEC(AM_ABSX, OP_STZ, W_M, 0, 1);
  // index loads/stores/compares
  t[0xA0] = DEC(AM_IMMX, OP_LDY, W_X, 1, 0); t[0xA4] = DEC(AM_DIR, OP_LDY, W_X, 1, 0);
  t[0xAC] = DEC(AM_ABS, OP_LDY, W_X, 1, 0); t[0xB4] = DEC(AM_DIRX, OP_LDY, W_X, 1, 0);
  t[0xBC] = DEC(AM_ABSX, OP_LDY, W_X, 1, 0);
  t[0xA2] = DEC(AM_IMMX, OP_LDX, W_X, 1, 0); t[0xA6] = DEC(AM_DIR, OP_LDX, W_X, 1, 0);
  t[0xAE] = DEC(AM_ABS, OP_LDX, W_X, 1, 0); t[0xB6] = DEC(AM_DIRY, OP_LDX, W_X, 1, 0);
  t[0xBE] = DEC(AM_ABSY, OP_LDX, W_X, 1, 0);
  t[0x84] = DEC(AM_DIR, OP_STY, W_X, 0, 1); t[0x8C] = DEC(AM_ABS, OP_STY, W_X, 0, 1);
  t[0x94] = DEC(AM_DIRX, OP_STY, W_X, 0, 1);
  t[0x86] = DEC(AM_DIR, OP_STX, W_X, 0, 1); t[0x8E] = DEC(AM_ABS, OP_STX, W_X, 0, 1);
  t[0x96] = DEC(AM_DIRY, OP_STX, W_X, 0, 1);
  t[0xC0] = DEC(AM_IMMX, OP_CPY, W_X, 1, 0); t[0xC4] = DEC(AM_DIR, OP_CPY, W_X, 1, 0);
  t[0xCC] = DEC(AM_ABS, OP_CPY, W_X, 1, 0);
  t[0xE0] = DEC(AM_IMMX, OP_CPX, W_X, 1, 0); t[0xE4] = DEC(AM_DIR, OP_CPX, W_X, 1, 0);
  t[0xEC] = DEC(AM_ABS, OP_CPX, W_X, 1, 0);
  // register inc/dec, transfers
  t[0xE8] = DEC(AM_IMP, OP_INX, W_X, 0, 0); t[0xC8] = DEC(AM_IMP, OP_INY, W_X, 0, 0);
  t[0xCA] = DEC(AM_IMP, OP_DEX, W_X, 0, 0); t[0x88] = DEC(AM_IMP, OP_DEY, W_X, 0, 0);
  t[0xAA] = DEC(AM_IMP, OP_TAX, W_X, 0, 0); t[0xA8] = DEC(AM_IMP, OP_TAY, W_X, 0, 0);
  t[0x8A] = DEC(AM_IMP, OP_TXA, W_M, 0, 0); t[0x98] = DEC(AM_IMP, OP_TYA, W_M, 0, 0);
  t[0x9B] = DEC(AM_IMP, OP_TXY, W_X, 0, 0); t[0xBB] = DEC(AM_IMP, OP_TYX, W_X, 0, 0);
  t[0xBA] = DEC(AM_IMP, OP_TSX, W_X, 0, 0); t[0x9A] = DEC(AM_IMP, OP_TXS, W_16, 0, 0);
  t[0x1B] = DEC(AM_IMP, OP_TCS, W_16, 0, 0); t[0x3B] = DEC(AM_IMP, OP_TSC, W_16, 0, 0);
  t[0x5B] = DEC(AM_IMP, OP_TCD, W_16, 0, 0); t[0x7B] = DEC(AM_IMP, OP_TDC, W_16, 0, 0);
  t[0xEB] = DEC(AM_IMP, OP_XBA, W_8, 0, 0); t[0xFB] = DEC(AM_IMP, OP_XCE, W_8, 0, 0);
  // branches
  t[0x10] = BR(0); t[0x30] = BR(1); t[0x50] = BR(2); t[0x70] = BR(3);
  t[0x90] = BR(4); t[0xB0] = BR(5); t[0xD0] = BR(6); t[0xF0] = BR(7);
  t[0x80] = BR(0);  // BRA: forced taken in the op
  t[0x82] = DEC(AM_REL16, OP_BRL, W_16, 0, 0);
  // jumps, calls, returns
  t[0x4C] = DEC(AM_ABSJMP, OP_JMP, W_16, 0, 0); t[0x6C] = DEC(AM_ABSIND, OP_JMP, W_16, 0, 0);
  t[0x7C] = DEC(AM_ABSXIND, OP_JMP, W_16, 0, 0);
  t[0x5C] = DEC(AM_ABSLJMP, OP_JML, W_16, 0, 0); t[0xDC] = DEC(AM_ABSINDL, OP_JML, W_16, 0, 0);
  t[0x20] = DEC(AM_ABSJMP, OP_JSR, W_16, 0, 0); t[0x22] = DEC(AM_IMP, OP_JSL, W_16, 0, 0);
  t[0xFC] = DEC(AM_IMP, OP_JSRXIND, W_16, 0, 0);
  t[0x60] = DEC(AM_IMP, OP_RTS, W_16, 0, 0); t[0x6B] = DEC(AM_IMP, OP_RTL, W_16, 0, 0);
  t[0x40] = DEC(AM_IMP, OP_RTI, W_16, 0, 0);
  t[0x00] = DEC(AM_IMM8, OP_BRK, W_8, 0, 0); t[0x02] = DEC(AM_IMM8, OP_COP, W_8, 0, 0);
  // stack
  t[0x48] = DEC(AM_IMP, OP_PHA, W_M, 0, 0); t[0xDA] = DEC(AM_IMP, OP_PHX, W_X, 0, 0);
  t[0x5A] = DEC(AM_IMP, OP_PHY, W_X, 0, 0); t[0x08] = DEC(AM_IMP, OP_PHP, W_8, 0, 0);
  t[0x8B] = DEC(AM_IMP, OP_PHB, W_8, 0, 0); t[0x0B] = DEC(AM_IMP, OP_PHD, W_16, 0, 0);
  t[0x4B] = DEC(AM_IMP, OP_PHK, W_8, 0, 0);
  t[0x68] = DEC(AM_IMP, OP_PLA, W_M, 0, 0); t[0xFA] = DEC(AM_IMP, OP_PLX, W_X, 0, 0);
  t[0x7A] = DEC(AM_IMP, OP_PLY, W_X, 0, 0); t[0x28] = DEC(AM_IMP, OP_PLP, W_8, 0, 0);
  t[0xAB] = DEC(AM_IMP, OP_PLB, W_8, 0, 0); t[0x2B] = DEC(AM_IMP, OP_PLD, W_16, 0, 0);
  t[0xF4] = DEC(AM_IMM16, OP_PEA, W_16, 0, 0); t[0xD4] = DEC(AM_DIR, OP_PEI, W_16, 0, 0);
  t[0x62] = DEC(AM_REL16, OP_PER, W_16, 0, 0);
  // flags
  t[0x18] = DEC(AM_IMP, OP_CLC, W_8, 0, 0); t[0x38] = DEC(AM_IMP, OP_SEC, W_8, 0, 0);
  t[0x58] = DEC(AM_IMP, OP_CLI, W_8, 0, 0); t[0x78] = DEC(AM_IMP, OP_SEI, W_8, 0, 0);
  t[0xD8] = DEC(AM_IMP, OP_CLD, W_8, 0, 0); t[0xF8] = DEC(AM_IMP, OP_SED, W_8, 0, 0);
  t[0xB8] = DEC(AM_IMP, OP_CLV, W_8, 0, 0);
  t[0xC2] = DEC(AM_IMM8, OP_REP, W_8, 0, 0); t[0xE2] = DEC(AM_IMM8, OP_SEP, W_8, 0, 0);
  // misc
  t[0xEA] = DEC(AM_IMP, OP_NOP, W_8, 0, 0); t[0x42] = DEC(AM_IMM8, OP_NOP, W_8, 0, 0);
  t[0xCB] = DEC(AM_IMP, OP_WAI, W_8, 0, 0); t[0xDB] = DEC(AM_IMP, OP_STP, W_8, 0, 0);
  t[0x54] = DEC(AM_BLK, OP_MVN, W_16, 0, 0); t[0x44] = DEC(AM_BLK, OP_MVP, W_16, 0, 0);
}
#endif
