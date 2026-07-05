class_name Sfx
## 程序化合成音效:启动时生成 AudioStreamWAV,无需外部音频资源。

const RATE := 32000


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## 麻将牌拍在桌面上的脆响(出牌)。
static func clack() -> AudioStreamWAV:
	var n := int(RATE * 0.10)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var hit := rng.randf_range(-1.0, 1.0) * exp(-t * 220.0) * 0.9
		var ring := (sin(TAU * 1420.0 * t) * 0.55 + sin(TAU * 2380.0 * t) * 0.3) * exp(-t * 70.0)
		var thump := sin(TAU * 170.0 * t) * exp(-t * 55.0) * 0.5
		s[i] = hit + ring + thump
	return _wav(s)


## 轻微的"嗒"声(摸牌、按钮)。
static func tick() -> AudioStreamWAV:
	var n := int(RATE * 0.06)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 2400.0 * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.2) \
				* exp(-t * 240.0) * 0.7
	return _wav(s)


## 低沉的闷响(吃/碰/杠)。
static func thud() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := 95.0 + 260.0 * exp(-t * 14.0)
		phase += TAU * freq / RATE
		s[i] = sin(phase) * exp(-t * 20.0) * 0.9 \
				+ rng.randf_range(-1.0, 1.0) * exp(-t * 150.0) * 0.25
	return _wav(s)


## 上行琶音(胡牌)。
static func fanfare() -> AudioStreamWAV:
	var n := int(RATE * 0.95)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.50]
	for j in notes.size():
		var f: float = notes[j]
		var start := j * 0.11
		var len := 0.55 if j == notes.size() - 1 else 0.30
		for i in int(len * RATE):
			var idx := int(start * RATE) + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var env := minf(t * 40.0, 1.0) * exp(-t * 6.0)
			s[idx] += (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.15 \
					+ sin(TAU * f * 0.5 * t) * 0.1) * env * 0.5
	return _wav(s)


## 下行双音(流局)。
static func sad() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [[392.0, 0.0], [311.13, 0.25]]
	for nd in notes:
		var f: float = nd[0]
		var start: float = nd[1]
		for i in int(0.4 * RATE):
			var idx := int(start * RATE) + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var env := minf(t * 30.0, 1.0) * exp(-t * 7.0)
			s[idx] += (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.1) * env * 0.5
	return _wav(s)


## 一连串细碎的洗牌/码牌声(发牌)。
static func shuffle() -> AudioStreamWAV:
	var n := int(RATE * 0.65)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _c in 16:
		var start := rng.randf_range(0.0, 0.5)
		var freq := rng.randf_range(1100.0, 2600.0)
		var amp := rng.randf_range(0.2, 0.4)
		for i in int(0.04 * RATE):
			var idx := int(start * RATE) + i
			if idx >= n:
				break
			var t := float(i) / RATE
			s[idx] += (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * freq * t) * 0.4) \
					* exp(-t * 300.0) * amp
	return _wav(s)
