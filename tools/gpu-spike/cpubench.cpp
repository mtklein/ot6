// cpubench.cpp -- the same core.h on host threads, as a baseline for the
// GPU numbers: N instances from the K checkpoints (instance i from
// checkpoint i % K, F frames each), spread over T threads, no per-frame
// checks; every instance's final registers and WRAM hashes are checked
// against the trace after the clock stops.
//
//   cpubench <capture> <rom> <checkpoints> <n> <threads> [K] [F]
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>
#include "replay.h"

int main(int argc, char** argv) {
  if (argc < 6) { fprintf(stderr, "usage: cpubench <capture> <rom> <ckpt> <n> <threads> [K] [F]\n"); return 2; }
  Capture cap = load_capture(argv[1], argv[2]);
  auto ckb = slurp(argv[3]);
  u32 N = (u32)atoi(argv[4]), T = (u32)atoi(argv[5]);
  u32 K = argc > 6 ? (u32)atoi(argv[6]) : 1;
  u32 nNmi = (u32)cap.nmi_at.size();
  u32 F = argc > 7 ? (u32)atoi(argv[7]) : nNmi - (K - 1);
  size_t sramSize = cap.sram.size(), ckSize = sizeof(Cpu) + 0x20000 + sramSize;
  std::vector<u32> dec(256);
  build_decode(dec.data());
  std::vector<std::vector<u8>> wram(N), sram(N);
  std::vector<Cpu> cpus(N), start(N);
  for (u32 i = 0; i < N; i++) {
    const u8* p = &ckb[(i % K) * ckSize];
    memcpy(&cpus[i], p, sizeof(Cpu));
    start[i] = cpus[i];
    wram[i].assign(p + sizeof(Cpu), p + sizeof(Cpu) + 0x20000);
    sram[i].assign(p + sizeof(Cpu) + 0x20000, p + ckSize);
  }
  std::atomic<u32> next{0};
  auto worker = [&]() {
    for (;;) {
      u32 i = next++;
      if (i >= N) return;
      Ctx c;
      c.wram = wram[i].data(); c.sram = sram[i].data(); c.rom = cap.rom.data(); c.map = cap.map.data();
      c.nmi_at = cap.nmi_at.data(); c.n_nmi = nNmi;
      c.io_at = cap.io_at.data(); c.io_val = cap.io_val.data(); c.n_io = (u32)cap.io_at.size();
      c.pad = cap.pad.data();
      c.stride = 1; c.sram_mask = (u32)sramSize - 1; c.io_check = 1;
      Cpu s = cpus[i];
      u32 target = s.frame + F;
      while (s.status == ST_OK && s.frame < target) { step(s, c, dec.data()); maybe_nmi(s, c); }
      cpus[i] = s;
    }
  };
  auto t0 = std::chrono::steady_clock::now();
  std::vector<std::thread> th;
  for (u32 t = 0; t < T; t++) th.emplace_back(worker);
  for (auto& t : th) t.join();
  double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  uint64_t instrs = 0, frames = 0;
  u32 bad = 0;
  for (u32 i = 0; i < N; i++) {
    instrs += cpus[i].icount - start[i].icount;
    frames += cpus[i].frame - start[i].frame;
    u32 h[128];
    wram_hashes(wram[i].data(), 1, h);
    u32 f = cpus[i].frame;
    if (cpus[i].status || f == 0 || !regs_match(cpus[i], cap.ints[f - 1].regs) || memcmp(h, cap.ints[f - 1].hash, 512)) bad++;
  }
  printf("CPU RESULT N=%u threads=%u stagger=%u: %llu instr, %llu frames in %.3f s -> %.0f frames/s, %.1f Minstr/s; %u of %u instances differ from Mesen at their last frame\n",
         N, T, K, (unsigned long long)instrs, (unsigned long long)frames, secs, frames / secs, instrs / secs / 1e6, bad, N);
  return bad ? 1 : 0;
}
