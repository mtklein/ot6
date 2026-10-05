#!/usr/bin/env python3
"""apply_variant_patch.py <mesen source dir> -- the render-cost experiment.

Adds env knobs (read once, at load) to OT6's Mesen (ot6-2.2.1-1, 40586fe8);
with none set the build behaves as the pinned one:
  OT6X_RENDER_EVERY=N  the SNES PPU draws pixels only on frames whose PPU frame
                       counter is a multiple of N (Mesen's own _skipRender path,
                       the one its frame skip uses); N=1000000000 ~ never.
  OT6X_SKIP_SEND=1     on a frame the PPU skipped, do not hand the (stale)
                       buffer to the decode thread (VideoDecoder::UpdateFrame);
                       still sends the PpuFrameDone notification.
  OT6X_NO_MIXER=1      Spc::ProcessEndFrame does not pass the DSP's samples to
                       SoundMixer::PlayAudioBuffer (resampler, rewind audio).
  OT6X_NO_DSP=1        PROBE ONLY, NOT emulation-safe by construction: Dsp::Exec
                       returns at once (no voices, envelopes, echo writes).
"""
import sys
src = sys.argv[1]

def edit(path, old, new):
    p = f"{src}/{path}"
    s = open(p).read()
    assert s.count(old) == 1, (path, old[:60])
    open(p, "w").write(s.replace(old, new, 1))

helper = '''//OT6 render-cost experiment (not for shipping): env knobs read once.
static int Ot6xEnvInt(const char* name)
{
	const char* v = std::getenv(name);
	return v ? atoi(v) : 0;
}
static const int _ot6xRenderEvery = Ot6xEnvInt("OT6X_RENDER_EVERY");
static const int _ot6xSkipSend = Ot6xEnvInt("OT6X_SKIP_SEND");

bool SnesPpu::ProcessEndOfScanline(uint16_t& hClock)'''
edit("Core/SNES/SnesPpu.cpp", "bool SnesPpu::ProcessEndOfScanline(uint16_t& hClock)", helper)
edit("Core/SNES/SnesPpu.cpp", '''			if(_emu->IsRunAheadFrame()) {
				_skipRender = true;
			}
''', '''			if(_emu->IsRunAheadFrame()) {
				_skipRender = true;
			}

			if(_ot6xRenderEvery > 0) {
				//Render only every Nth frame (by the PPU's frame counter)
				_skipRender = (_frameCount % (uint32_t)_ot6xRenderEvery) != 0;
			}
''')
edit("Core/SNES/SnesPpu.cpp", '''void SnesPpu::SendFrame()
{
''', '''void SnesPpu::SendFrame()
{
	if(_ot6xSkipSend && _skipRender) {
		//No new pixels: don't hand the decode thread a stale frame to convert
		_emu->GetNotificationManager()->SendNotification(ConsoleNotificationType::PpuFrameDone);
		return;
	}
''')
edit("Core/SNES/Spc.cpp", '''	if(sampleCount != 0) {
		_emu->GetSoundMixer()->PlayAudioBuffer(''', '''	static const bool ot6xNoMixer = std::getenv("OT6X_NO_MIXER") && std::getenv("OT6X_NO_MIXER")[0] == '1';
	if(sampleCount != 0 && !ot6xNoMixer) {
		_emu->GetSoundMixer()->PlayAudioBuffer(''')
edit("Core/SNES/DSP/Dsp.cpp", '''void Dsp::Exec()
{
''', '''void Dsp::Exec()
{
	static const bool ot6xNoDsp = std::getenv("OT6X_NO_DSP") && std::getenv("OT6X_NO_DSP")[0] == '1';
	if(ot6xNoDsp) {
		return;
	}
''')
print("patched", src)
