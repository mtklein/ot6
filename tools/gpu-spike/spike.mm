// spike.mm -- run N instances of core.h on the GPU (Metal) replaying the
// captured segment, time them, and check every instance against Mesen.
//
//   spike <capture dir> <rom> <checkpoints> <n> [options]
//     --layout contig|interleave   WRAM/SRAM layout (default interleave)
//     --stagger K                  instance i starts at checkpoint i % K (default 1)
//     --frames F                   frames each instance runs (default 600 - K + 1... capped)
//     --chunk C                    frames per dispatch (default 4)
//     --tg T                       threads per threadgroup (default 64)
//     --no-check-final             skip the host-side final WRAM hash check
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <chrono>
#include <string>
#include <vector>
#include "replay.h"

struct Params {
  uint32_t n, stride, sram_size, n_frames, n_nmi, n_io, frames_per_dispatch, io_check;
};

static std::string read_text(const std::string& p) {
  auto b = slurp(p);
  return std::string(b.begin(), b.end());
}

int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc < 5) { fprintf(stderr, "usage: spike <capture> <rom> <checkpoints> <n> [opts]\n"); return 2; }
    std::string capDir = argv[1], romPath = argv[2], ckPath = argv[3];
    uint32_t N = (uint32_t)atoi(argv[4]);
    bool interleave = true, checkFinal = true;
    uint32_t K = 1, F = 0, chunk = 4, tg = 64, B = 32;
    for (int i = 5; i < argc; i++) {
      std::string a = argv[i];
      if (a == "--layout") interleave = std::string(argv[++i]) == "interleave";
      else if (a == "--stagger") K = (uint32_t)atoi(argv[++i]);
      else if (a == "--frames") F = (uint32_t)atoi(argv[++i]);
      else if (a == "--chunk") chunk = (uint32_t)atoi(argv[++i]);
      else if (a == "--tg") tg = (uint32_t)atoi(argv[++i]);
      else if (a == "--block") B = (uint32_t)atoi(argv[++i]);
      else if (a == "--no-check-final") checkFinal = false;
      else { fprintf(stderr, "unknown option %s\n", a.c_str()); return 2; }
    }
    Capture cap = load_capture(capDir, romPath);
    uint32_t nNmi = (uint32_t)cap.nmi_at.size();
    if (F == 0) F = nNmi - (K - 1);
    if (K - 1 + F > nNmi) { fprintf(stderr, "stagger + frames exceed the segment\n"); return 2; }

    // checkpoints written by ref: Cpu | WRAM | SRAM, frames 0..K-1
    auto ckb = slurp(ckPath);
    size_t sramSize = cap.sram.size();
    size_t ckSize = sizeof(Cpu) + 0x20000 + sramSize;
    if (ckb.size() < K * ckSize) { fprintf(stderr, "need %u checkpoints, file has %zu\n", K, ckb.size() / ckSize); return 2; }

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    std::string src = std::string("#include <metal_stdlib>\nusing namespace metal;\n") + read_text(std::string(SPIKE_DIR) + "/core.h") + "\n" + read_text(std::string(SPIKE_DIR) + "/kernel.metal");
    NSError* err = nil;
    MTLCompileOptions* opts = [MTLCompileOptions new];
    opts.mathMode = MTLMathModeSafe;
    id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:src.c_str()] options:opts error:&err];
    if (!lib) { fprintf(stderr, "compile: %s\n", err.localizedDescription.UTF8String); return 2; }
    id<MTLFunction> fn = [lib newFunctionWithName:@"run"];
    id<MTLComputePipelineState> pso = [dev newComputePipelineStateWithFunction:fn error:&err];
    if (!pso) { fprintf(stderr, "pipeline: %s\n", err.localizedDescription.UTF8String); return 2; }
    id<MTLCommandQueue> q = [dev newCommandQueue];

    auto mk = [&](const void* p, size_t n) {
      return p ? [dev newBufferWithBytes:p length:n options:MTLResourceStorageModeShared]
               : [dev newBufferWithLength:n options:MTLResourceStorageModeShared];
    };
    std::vector<u32> dec(256);
    build_decode(dec.data());
    uint32_t nFrames = nNmi + 1;
    std::vector<u16> pads((size_t)N * nFrames);
    for (uint32_t i = 0; i < N; i++) memcpy(&pads[(size_t)i * nFrames], cap.pad.data(), nFrames * 2);
    std::vector<u32> want(4 * nNmi);
    for (uint32_t f = 0; f < nNmi; f++) {
      const Regs& r = cap.ints[f].regs;
      want[4 * f + 0] = r.a | (r.x << 16);
      want[4 * f + 1] = r.y | (r.sp << 16);
      want[4 * f + 2] = r.d | (r.pc << 16);
      want[4 * f + 3] = r.dbr | (r.k << 8) | (r.ps << 16) | ((u32)r.emu << 24);
    }
    std::vector<u32> target(N);
    std::vector<Cpu> cpus(N);
    for (uint32_t i = 0; i < N; i++) {
      uint32_t j = i % K;
      memcpy(&cpus[i], &ckb[j * ckSize], sizeof(Cpu));
      target[i] = cpus[i].frame + F;
    }
    id<MTLBuffer> bCpu = mk(cpus.data(), sizeof(Cpu) * N);
    uint32_t S = interleave ? B : 1u;               // byte stride
    size_t NR = ((size_t)N + S - 1) / S * S;          // instances rounded up to whole blocks
    auto wbase = [&](size_t i) { return (i / S) * S * 0x20000 + i % S; };
    auto sbase = [&](size_t i) { return (i / S) * S * sramSize + i % S; };
    id<MTLBuffer> bWram = mk(nullptr, NR * 0x20000);
    id<MTLBuffer> bSram = mk(nullptr, NR * sramSize);
    if (!bWram || !bSram) { fprintf(stderr, "cannot allocate %zu bytes of WRAM\n", NR * 0x20000); return 2; }
    {
      u8* w = (u8*)bWram.contents; u8* sr = (u8*)bSram.contents;
      for (uint32_t i = 0; i < N; i++) {
        const u8* cw = &ckb[(i % K) * ckSize + sizeof(Cpu)];
        const u8* cs = cw + 0x20000;
        u8* wi = w + wbase(i); u8* si = sr + sbase(i);
        for (size_t a = 0; a < 0x20000; a++) wi[a * S] = cw[a];
        for (size_t a = 0; a < sramSize; a++) si[a * S] = cs[a];
      }
    }
    id<MTLBuffer> bRom = mk(cap.rom.data(), cap.rom.size());
    id<MTLBuffer> bMap = mk(cap.map.data(), 4 * cap.map.size());
    id<MTLBuffer> bDec = mk(dec.data(), 4 * 256);
    id<MTLBuffer> bNmi = mk(cap.nmi_at.data(), 4 * cap.nmi_at.size());
    id<MTLBuffer> bIoAt = mk(cap.io_at.data(), 4 * cap.io_at.size());
    id<MTLBuffer> bIoVal = mk(cap.io_val.data(), 4 * cap.io_val.size());
    id<MTLBuffer> bPad = mk(pads.data(), 2 * pads.size());
    id<MTLBuffer> bWant = mk(want.data(), 4 * want.size());
    id<MTLBuffer> bTarget = mk(target.data(), 4 * N);
    Params P = { N, S, (uint32_t)sramSize, nFrames, nNmi, (uint32_t)cap.io_at.size(), chunk, 1 };

    uint64_t icount0 = 0;
    for (auto& s : cpus) icount0 += s.icount;
    double gpuSecs = 0;
    int dispatches = 0;
    auto t0 = std::chrono::steady_clock::now();
    uint32_t maxTarget = 0;
    for (auto t : target) maxTarget = std::max(maxTarget, t);
    uint32_t minStart = 0xFFFFFFFF;
    for (auto& s : cpus) minStart = std::min(minStart, s.frame);
    for (uint32_t done = minStart; done < maxTarget; done += chunk) {
      id<MTLCommandBuffer> cb = [q commandBuffer];
      id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
      [enc setComputePipelineState:pso];
      id<MTLBuffer> bufs[] = { bCpu, bWram, bSram, bRom, bMap, bDec, bNmi, bIoAt, bIoVal, bPad, bWant, bTarget };
      for (int b = 0; b < 12; b++) [enc setBuffer:bufs[b] offset:0 atIndex:b];
      [enc setBytes:&P length:sizeof P atIndex:12];
      [enc dispatchThreads:MTLSizeMake(N, 1, 1) threadsPerThreadgroup:MTLSizeMake(std::min<uint32_t>(tg, N), 1, 1)];
      [enc endEncoding];
      [cb commit];
      [cb waitUntilCompleted];
      if (cb.status != MTLCommandBufferStatusCompleted) {
        fprintf(stderr, "command buffer failed: %s\n", cb.error.localizedDescription.UTF8String);
        return 3;
      }
      gpuSecs += cb.GPUEndTime - cb.GPUStartTime;
      dispatches++;
    }
    double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

    Cpu* out = (Cpu*)bCpu.contents;
    uint64_t icount1 = 0, frames = 0;
    uint32_t nDone = 0, nRegBad = 0, nHashBad = 0, nStatusBad = 0;
    uint32_t firstBad = 0xFFFFFFFF;
    std::map<uint32_t, uint32_t> statusCount;
    for (uint32_t i = 0; i < N; i++) {
      icount1 += out[i].icount;
      frames += out[i].frame - cpus[i].frame;
      statusCount[out[i].status]++;
      if (out[i].status == ST_DONE) nDone++; else nStatusBad++;
      if (out[i].first_bad_frame != 0xFFFFFFFF) { nRegBad++; firstBad = std::min(firstBad, out[i].first_bad_frame); }
    }
    if (checkFinal) {
      const u8* w = (const u8*)bWram.contents;
      for (uint32_t i = 0; i < N; i++) {
        u32 h[128];
        wram_hashes(w + wbase(i), S, h);
        uint32_t f = out[i].frame;
        if (f == 0 || memcmp(h, cap.ints[f - 1].hash, 512) != 0) nHashBad++;
      }
    }
    uint64_t instrs = icount1 - icount0;
    printf("device: %s\n", dev.name.UTF8String);
    printf("config: N=%u layout=%s stride=%u stagger=%u frames/instance=%u chunk=%u tg=%u dispatches=%d\n",
           N, interleave ? "interleave" : "contig", S, K, F, chunk, tg, dispatches);
    printf("status:");
    for (auto& kv : statusCount) printf(" %u:%u", kv.first, kv.second);
    printf("  (1 = finished)\n");
    printf("correctness: %u/%u instances finished, %u with a register mismatch at an NMI (first at frame %d), %s\n",
           nDone, N, nRegBad, firstBad == 0xFFFFFFFF ? -1 : (int)firstBad,
           checkFinal ? ([NSString stringWithFormat:@"%u final WRAM hash mismatches", nHashBad]).UTF8String : "final WRAM not checked");
    printf("RESULT N=%u layout=%s stagger=%u: %llu instr, %llu frames, wall %.3f s, gpu %.3f s -> %.0f frames/s (wall), %.0f frames/s (gpu), %.1f Minstr/s (wall)\n",
           N, interleave ? "interleave" : "contig", K, (unsigned long long)instrs, (unsigned long long)frames,
           wall, gpuSecs, frames / wall, frames / gpuSecs, instrs / wall / 1e6);
    return (nStatusBad == 0 && nRegBad == 0 && nHashBad == 0) ? 0 : 1;
  }
}
