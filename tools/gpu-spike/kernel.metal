// kernel.metal -- one GPU thread per emulated SNES CPU.  The host
// concatenates core.h in front of this file and compiles it at run time.
#include <metal_stdlib>
using namespace metal;
// (core.h is pasted here by the host)

struct Params {
  uint n;            // instances
  uint stride;       // 1 = instance-contiguous WRAM/SRAM, B = interleaved in blocks of B
  uint sram_size;
  uint n_frames;     // frames in the pad table per instance
  uint n_nmi, n_io;
  uint frames_per_dispatch;
  uint io_check;
};

// expected registers at each NMI entry, 4 words per frame:
//   a | x << 16, y | sp << 16, d | pc << 16, dbr | k << 8 | p << 16 | e << 24
kernel void run(device Cpu* cpus [[buffer(0)]],
                device uchar* wram [[buffer(1)]],
                device uchar* sram [[buffer(2)]],
                device const uchar* rom [[buffer(3)]],
                device const uint* map [[buffer(4)]],
                device const uint* dectab [[buffer(5)]],
                device const uint* nmi_at [[buffer(6)]],
                device const uint* io_at [[buffer(7)]],
                device const uint* io_val [[buffer(8)]],
                device const ushort* pad [[buffer(9)]],
                device const uint* want [[buffer(10)]],
                device const uint* target [[buffer(11)]],
                constant Params& P [[buffer(12)]],
                uint lane [[thread_position_in_grid]]) {
  if (lane >= P.n) return;
  Cpu s = cpus[lane];
  Ctx c;
  c.wram = wram; c.sram = sram; c.rom = rom; c.map = map;
  c.nmi_at = nmi_at; c.n_nmi = P.n_nmi;
  c.io_at = io_at; c.io_val = io_val; c.n_io = P.n_io;
  c.pad = pad + lane * P.n_frames;
  c.stride = P.stride;
  ulong blk = lane / P.stride, sub = lane % P.stride;
  c.wram = wram + blk * (ulong)P.stride * 0x20000ul + sub;
  c.sram = sram + blk * (ulong)P.stride * (ulong)P.sram_size + sub;
  c.sram_mask = P.sram_size - 1;
  c.io_check = P.io_check;
  uint stop = min(s.frame + P.frames_per_dispatch, target[lane]);
  while (s.status == ST_OK && s.frame < stop) {
    step(s, c, dectab);
    if (maybe_nmi(s, c)) {
      device const uint* w = want + 4 * (s.frame - 1);
      bool ok = (s.a | (s.x << 16)) == w[0] && (s.y | (s.sp << 16)) == w[1] &&
                (s.d | (s.pc << 16)) == w[2] && (s.dbr | (s.k << 8) | (s.p << 16) | (s.e << 24)) == w[3];
      if (!ok && s.first_bad_frame == 0xFFFFFFFFu) s.first_bad_frame = s.frame;
    }
  }
  if (s.status == ST_OK && s.frame >= target[lane]) s.status = ST_DONE;
  cpus[lane] = s;
}
