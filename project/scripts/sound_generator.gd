extends Node

# ─────────────────────────────────────────
#  Sound Generator — Procedural Audio
#  Generates all game SFX from scratch using
#  AudioStreamWAV + math. No audio files needed.
# ─────────────────────────────────────────

# ── Public API ────────────────────────────────────────────────────────────────

static func gunshot() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.35
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		# Thump: low-frequency sine burst
		var thump := sin(TAU * 110.0 * t) * exp(-t * 22.0) * 0.7
		# Body: mid-frequency crack
		var crack := sin(TAU * 600.0 * t) * exp(-t * 40.0) * 0.5
		# Noise tail: filtered white noise
		var noise := _noise(i) * exp(-t * 12.0) * 0.6
		# High-freq snap at attack
		var snap  := sin(TAU * 2200.0 * t) * exp(-t * 80.0) * 0.4
		var raw := thump + crack + noise + snap
		# Waveshaper saturation (soft clip)
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 1.4)), -1.0, 1.0)
	return _make_wav(s, sr)


static func gunshot_shotgun() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.55
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		# Massive layered thumps for body weight
		var thump1 := sin(TAU * 65.0 * t) * exp(-t * 14.0) * 0.9
		var thump2 := sin(TAU * 125.0 * t) * exp(-t * 24.0) * 0.5
		# Loud metal mid crack
		var crack := sin(TAU * 380.0 * t) * exp(-t * 28.0) * 0.4
		# Heavy white noise explosion tail
		var noise := _noise(i) * exp(-t * 8.5) * 0.8
		var raw := thump1 + thump2 + crack + noise
		# Heavy waveshaper distortion for chest-thumping impact
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 2.2)), -1.0, 1.0)
	return _make_wav(s, sr)


static func gunshot_sniper() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.75
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		# Chest-thumping ultra-low sub boom
		var thump := sin(TAU * 50.0 * t) * exp(-t * 6.5) * 1.0
		# High frequency whiplash snap
		var crack := sin(TAU * 880.0 * t) * exp(-t * 30.0) * 0.6
		var snap  := sin(TAU * 3200.0 * t) * exp(-t * 110.0) * 0.5
		# Long metallic ringing noise tail (reverb simulation)
		var noise := _noise(i) * exp(-t * 4.2) * 0.45
		var raw := thump + crack + snap + noise
		# Saturated soft-clip
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 1.8)), -1.0, 1.0)
	return _make_wav(s, sr)


static func gunshot_pistol() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.22
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var thump := sin(TAU * 160.0 * t) * exp(-t * 30.0) * 0.6
		var crack := sin(TAU * 700.0 * t) * exp(-t * 50.0) * 0.4
		var noise := _noise(i) * exp(-t * 18.0) * 0.35
		var snap  := sin(TAU * 2600.0 * t) * exp(-t * 95.0) * 0.3
		var raw := thump + crack + noise + snap
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 1.5)), -1.0, 1.0)
	return _make_wav(s, sr)


static func gunshot_smg() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.16
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var thump := sin(TAU * 130.0 * t) * exp(-t * 35.0) * 0.55
		var crack := sin(TAU * 650.0 * t) * exp(-t * 45.0) * 0.45
		var noise := _noise(i) * exp(-t * 22.0) * 0.5
		var snap  := sin(TAU * 2800.0 * t) * exp(-t * 110.0) * 0.4
		var raw := thump + crack + noise + snap
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 1.6)), -1.0, 1.0)
	return _make_wav(s, sr)


static func gunshot_rocket() -> AudioStreamWAV:
	var sr := 22050
	var dur := 1.2
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		# Low end rumble/explosion
		var rumble := sin(TAU * 45.0 * t) * exp(-t * 4.0) * 1.1
		var thump  := sin(TAU * 95.0 * t) * exp(-t * 6.5) * 0.8
		var crack  := sin(TAU * 220.0 * t) * exp(-t * 12.0) * 0.6
		# Long heavy white noise tail
		var noise  := _noise(i) * exp(-t * 3.5) * 0.95
		var raw := rumble + thump + crack + noise
		s[i] = clamp(sign(raw) * (1.0 - exp(-abs(raw) * 2.5)), -1.0, 1.0)
	return _make_wav(s, sr)



static func impact_spark() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.18
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var click := sin(TAU * 800.0 * t) * exp(-t * 60.0) * 0.6
		var fizz  := _noise(i) * exp(-t * 25.0) * 0.5
		s[i] = clamp(click + fizz, -1.0, 1.0)
	return _make_wav(s, sr)


static func footstep() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.12
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var thump := sin(TAU * 80.0 * t) * exp(-t * 30.0) * 0.8
		var scuff := _noise(i) * exp(-t * 40.0) * 0.35
		s[i] = clamp(thump + scuff, -1.0, 1.0)
	return _make_wav(s, sr)


static func reload_click() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.08
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var tick := sin(TAU * 1400.0 * t) * exp(-t * 90.0) * 0.7
		var clack := sin(TAU * 300.0 * t) * exp(-t * 50.0) * 0.4
		s[i] = clamp(tick + clack, -1.0, 1.0)
	return _make_wav(s, sr)


static func reload_mag() -> AudioStreamWAV:
	# Sliding/clunk sound for mag seating
	var sr := 22050
	var dur := 0.22
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var slide := _noise(i) * exp(-t * 18.0) * 0.45
		var seat  := sin(TAU * 200.0 * t) * exp(-abs(t - 0.18) * 50.0) * 0.5
		s[i] = clamp(slide + seat, -1.0, 1.0)
	return _make_wav(s, sr)


static func empty_click() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.05
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		s[i] = sin(TAU * 2800.0 * t) * exp(-t * 120.0) * 0.5
	return _make_wav(s, sr)


static func enemy_grunt() -> AudioStreamWAV:
	# Descending pitch — "ugh" sound
	var sr := 22050
	var dur := 0.25
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var freq: float = lerp(320.0, 140.0, t / dur)
		var voice := sin(TAU * freq * t) * exp(-t * 8.0) * 0.6
		var noise := _noise(i) * exp(-t * 15.0) * 0.2
		s[i] = clamp(voice + noise, -1.0, 1.0)
	return _make_wav(s, sr)


static func enemy_die() -> AudioStreamWAV:
	# Heavier thud
	var sr := 22050
	var dur := 0.4
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var freq: float = lerp(200.0, 60.0, t / dur)
		var groan := sin(TAU * freq * t) * exp(-t * 6.0) * 0.55
		var thud  := sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.5
		var noise := _noise(i) * exp(-t * 20.0) * 0.15
		s[i] = clamp(groan + thud + noise, -1.0, 1.0)
	return _make_wav(s, sr)


static func enemy_alert() -> AudioStreamWAV:
	# Rising "!" stab sound
	var sr := 22050
	var dur := 0.15
	var n := int(sr * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / sr
		var freq: float = lerp(200.0, 800.0, t / dur)
		s[i] = sin(TAU * freq * t) * exp(-t * 10.0) * 0.5
	return _make_wav(s, sr)


# ── Internal helpers ──────────────────────────────────────────────────────────

static var _rng := RandomNumberGenerator.new()

static func _noise(seed_offset: int) -> float:
	_rng.seed = seed_offset * 1664525 + 1013904223
	return _rng.randf_range(-1.0, 1.0)


static func _make_wav(samples: PackedFloat32Array, sample_rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clamp(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2]     = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo   = false
	wav.data     = data
	return wav
