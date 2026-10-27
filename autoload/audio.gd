extends Node
## Music (cross-faded loops) + pooled one-shot SFX.

const MUSIC_DIR := "res://assets/audio/loop_musics/"
const MENU_MUSIC := "25 - Wayfinding.mp3"
# One loop per level theme (BLOCKS, ORBIT, TIDE, PHANTOM, SPIRAL, CHAOS)
const THEME_MUSIC := ["16 - Four Square.mp3", "20 - Ccc.mp3", "33 - Ditty.mp3",
	"50 - Spell.mp3", "40 - Yako.mp3", "89 - Trial.mp3"]
const MUSIC_DB := -8.0
const POOL_SIZE := 16

var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _pool: Array[AudioStreamPlayer] = []
var _sfx := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep music + UI sounds while paused
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_music.append(p)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for f in DirAccess.get_files_at("res://assets/audio/sfx/"):
		f = f.trim_suffix(".import").trim_suffix(".remap")  # exported builds list .import files
		if f.ends_with(".wav"): _sfx[f.get_basename()] = load("res://assets/audio/sfx/" + f)

func play_music(file: String, fade := 1.0) -> void:
	if file == _current: return
	_current = file
	var old := _music[_active]
	_active = 1 - _active
	var p := _music[_active]
	var stream = load(MUSIC_DIR + file)
	stream.loop = true
	p.stream = stream
	p.volume_db = -40.0
	p.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "volume_db", MUSIC_DB, fade)
	tw.tween_property(old, "volume_db", -40.0, fade)
	tw.chain().tween_callback(old.stop)

func play_theme_music(theme_index: int) -> void:
	play_music(THEME_MUSIC[theme_index % THEME_MUSIC.size()])

func stop_music(fade := 1.0) -> void:
	_current = ""
	create_tween().tween_property(_music[_active], "volume_db", -40.0, fade)

## Play a one-shot by file name (no extension) from assets/audio/sfx.
func sfx(sfx_name: String, volume_db := 0.0, pitch_jitter := 0.0, pitch := 1.0) -> void:
	if not _sfx.has(sfx_name): return
	for p in _pool:
		if not p.playing:
			p.stream = _sfx[sfx_name]
			p.volume_db = volume_db
			p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
			p.play()
			return

## Pentatonic steps: combo hits climb a scale instead of repeating one note.
const SCALE := [0, 2, 4, 7, 9, 12]  # caps at one octave so long combos stay pleasant

func combo_pitch(combo: int) -> float:
	var step: int = SCALE[clamp(combo - 1, 0, SCALE.size() - 1)]
	return pow(2.0, step / 12.0)

## Hook UI sounds onto every button under `root`.
func wire_buttons(root: Node) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		b.focus_entered.connect(sfx.bind("ui_focus", -10.0))
		b.pressed.connect(sfx.bind("ui_press", -4.0))
