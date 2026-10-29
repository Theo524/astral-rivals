extends Node
## All audio is generated from authored oscillators/noise. No sampled or licensed
## third-party assets are required. Replace streams in `sounds` for a final mix.
const RATE := 22050
var sounds: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var volume := 0.6
var music_enabled := true
var _voice_index := 0
var _rng := RandomNumberGenerator.new()
var _shutting_down: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 840127
	for i in 12:
		var voice := AudioStreamPlayer.new()
		voice.max_polyphony = 1
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(voice)
		voices.append(voice)
	for cue in ["hit", "heavy", "blast", "beam", "charge", "dash", "dodge", "transform", "explosion", "menu", "guard", "parry", "win", "lose"]:
		sounds[cue] = _synthesize(cue)
	music = AudioStreamPlayer.new()
	music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(music)
	music.stream = _make_music()

	_apply_volume()
	music.play()

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	# Stop players and release the node's references before freeing the manager.
	# AudioServer retires its own playback references on the NEXT audio mix, not
	# on the next SceneTree frame. Fixed-FPS/headless runs can advance thousands
	# of scene frames inside one audio buffer, so waiting scene frames is unsafe.
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	voices.clear()
	sounds.clear()
	# Synchronize with the actual remaining audio buffer period, rather than an
	# arbitrary fixed sleep. With the headless Dummy driver one buffer is ~93ms.
	# Real device drivers never block here. Accelerated graphical movie capture
	# also uses Dummy, so testing only the headless DISPLAY missed that path.
	if AudioServer.get_driver_name() == "Dummy":
		var remaining_mix_usec := int(ceil(AudioServer.get_time_to_next_mix()*1000000.0))
		if remaining_mix_usec > 0:
			OS.delay_usec(mini(remaining_mix_usec,100000))

func play(cue: String) -> void:
	if _shutting_down or voices.is_empty() or volume <= 0.001:
		return
	var aliases := {"light": "hit", "punch": "hit", "kick": "heavy", "attack": "hit", "hurt": "hit", "sphere": "blast", "homing": "blast", "ultimate": "beam", "nova": "explosion", "block": "guard", "counter": "parry", "fly": "dash", "victory": "win", "defeat": "lose", "click": "menu"}
	cue = aliases.get(cue, cue)
	if not sounds.has(cue):
		return
	var voice := voices[_voice_index]
	_voice_index = (_voice_index + 1) % voices.size()
	voice.stream = sounds[cue]
	voice.pitch_scale = _rng.randf_range(0.93, 1.07) if cue in ["hit", "heavy", "blast", "dash"] else 1.0
	voice.play()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply_volume()

func _apply_volume() -> void:
	var decibels := linear_to_db(maxf(volume, 0.0001))
	for voice in voices:
		voice.volume_db = decibels - 3.0
	if is_instance_valid(music):
		music.volume_db = decibels - 15.0

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not is_instance_valid(music):
		return
	if enabled and not music.playing:
		music.play()
	elif not enabled:
		music.stop()

func set_suspended(suspended: bool) -> void:
	# Used on app focus loss/resume without regenerating PCM resources.
	for voice in voices:
		if is_instance_valid(voice):
			voice.stream_paused = suspended
	if is_instance_valid(music):
		music.stream_paused = suspended

func _stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

func _synthesize(cue: String) -> AudioStreamWAV:
	var durations := {"hit": 0.13, "heavy": 0.25, "blast": 0.22, "beam": 0.85,
		"charge": 0.5, "dash": 0.18, "dodge": 0.18, "transform": 1.2,
		"explosion": 0.7, "menu": 0.09, "guard": 0.17, "parry": 0.32,
		"win": 0.9, "lose": 0.8}
	var duration: float = durations[cue]
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	var low_noise := 0.0
	for i in count:
		var t := float(i) / RATE
		var p := t / duration
		var noise := _rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.18)
		var sample := 0.0
		var envelope := pow(1.0 - p, 2.0) * minf(t * 800.0, 1.0)
		match cue:
			"hit", "heavy":
				var hz := (140.0 if cue == "hit" else 90.0) * (1.0 - p * 0.6)
				phase += TAU * hz / RATE
				sample = sin(phase) * 0.55 + noise * 0.5 * exp(-p * 7.0) + low_noise * 0.5
			"blast":
				phase += TAU * lerpf(1050.0, 120.0, p) / RATE
				sample = sin(phase) * 0.58 + sin(phase * 1.5) * 0.15 + noise * 0.17
			"beam":
				phase += TAU * (135.0 + 32.0 * sin(t * 50.0)) / RATE
				sample = sin(phase) * 0.25 + sin(phase * 2.02) * 0.2 + low_noise * 1.6
				envelope = minf(p * 9.0, 1.0) * minf((1.0 - p) * 5.0, 1.0)
			"charge", "transform":
				phase += TAU * lerpf(100.0, 650.0 if cue == "transform" else 420.0, p) / RATE
				sample = sin(phase) * 0.35 + sin(phase * 1.005) * 0.3 + sin(phase * 2.0) * 0.1 + low_noise * 0.3
				envelope = minf(p * 7.0, 1.0) * pow(1.0 - p, 0.6)
			"dash", "dodge":
				phase += TAU * lerpf(700.0, 150.0, p) / RATE
				sample = low_noise * 2.0 + sin(phase) * 0.12
			"explosion":
				phase += TAU * lerpf(85.0, 30.0, p) / RATE
				sample = low_noise * 2.2 + sin(phase) * 0.4 + noise * 0.15
			"menu":
				phase += TAU * (880.0 if p < 0.4 else 1320.0) / RATE
				sample = sin(phase) * 0.6
			"guard", "parry":
				phase += TAU * (430.0 if cue == "guard" else 1350.0) / RATE
				sample = sin(phase) * 0.4 + sin(phase * 2.17) * 0.2 + noise * 0.12
			"win", "lose":
				var notes: Array = [523.25, 659.25, 783.99, 1046.5] if cue == "win" else [392.0, 329.63, 293.66, 261.63]
				var note: float = notes[mini(3, int(p * 4.0))]
				phase += TAU * note / RATE
				sample = sin(phase) * 0.4 + sin(phase * 2.0) * 0.15
		var integer := int(clampf(sample * envelope * 0.65, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, integer)
	return _stream(bytes)

func _make_music() -> AudioStreamWAV:
	# Original four-bar pulse: D minor / Bb / F / C with a sparse upper motif.
	var beat := 0.4
	var duration := beat * 16.0
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var roots: Array[float] = [73.416, 58.270, 87.307, 65.406]
	var melody: Array[float] = [293.66, 0.0, 349.23, 440.0, 466.16, 440.0, 349.23, 0.0, 349.23, 440.0, 523.25, 440.0, 392.0, 349.23, 329.63, 261.63]
	for i in count:
		var t := float(i) / RATE
		var beat_index := int(t / beat)
		var local := fmod(t, beat)
		var chord_index := mini(3, beat_index / 4)
		var root: float = roots[chord_index]
		var bass := sin(TAU * root * t) * 0.25 * exp(-local * 5.0)
		var chord := (sin(TAU * root * 4.0 * t) + sin(TAU * root * 6.0 * t)) * 0.04
		var kick := sin(TAU * (50.0 * local + 9.0 * (1.0 - exp(-local * 25.0)))) * exp(-local * 30.0) * 0.4
		var hat_time := fmod(t, beat * 0.5)
		var hat := _rng.randf_range(-1.0, 1.0) * exp(-hat_time * 110.0) * 0.055
		var frequency: float = melody[mini(15, beat_index)]
		var lead := sin(TAU * frequency * t) * exp(-local * 8.0) * 0.12 if frequency > 0.0 else 0.0
		var sample := clampf(bass + chord + kick + hat + lead, -1.0, 1.0)
		# Tiny boundary fades suppress PCM loop discontinuities.
		sample *= minf(t * 90.0, 1.0) * minf((duration - t) * 90.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := _stream(bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream
