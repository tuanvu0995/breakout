extends Node
## OTA patch loader + update checker. Must be the FIRST autoload so patches are
## mounted before any packed resource loads. Same scheme as drivedrive:
## - A patch is a Godot patch .pck built against one shipped base version.
## - Downloaded patches apply on the NEXT launch (never hot-swapped).
## - Only one patch is kept: each patch is a full delta from the base build.
## Manifest comes from breakout-api: GET <api_url>/ota/manifest.

signal update_ready(patch_version: String)       ## staged, applies on restart
signal full_update_available(url: String)        ## engine change: needs store update

const PATCH_DIR := "user://ota/patches"
const STATE_PATH := "user://ota/state.cfg"

static var effective_version := ""
var base_version := ""
var applied := ""
var _http: HTTPRequest
var _overlay: CanvasLayer
var _bar: ProgressBar
var _status: Label
var _buttons: HBoxContainer

static func platform() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"macOS": return "macos"
		"Linux", "FreeBSD": return "linux"
		"Android": return "android"
		"iOS": return ""  # App Store forbids downloaded code: no OTA on iOS
		"Web": return "web"
	return ""

func _api_url() -> String:
	return str(ProjectSettings.get_setting("breakout/api_url", ""))

func _enter_tree() -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	effective_version = base_version
	# Never mount patches in the editor: they would shadow local edits.
	if _api_url() == "" or OS.has_feature("editor"): return
	DirAccess.make_dir_recursive_absolute(PATCH_DIR)
	var st := ConfigFile.new()
	st.load(STATE_PATH)
	applied = str(st.get_value("patch", "applied_version", ""))
	var revoked: Array = st.get_value("patch", "revoked", [])
	# Patch was built for another base (game reinstalled/updated): drop it.
	if applied != "" and (str(st.get_value("patch", "applied_base", "")) != base_version or applied in revoked):
		_wipe()
		applied = ""
	if applied != "":
		var path := PATCH_DIR.path_join("patch-%s.pck" % applied)
		if FileAccess.file_exists(path) and ProjectSettings.load_resource_pack(path):
			effective_version = applied
		else:
			_wipe()
			applied = ""

func _wipe() -> void:
	DirAccess.make_dir_recursive_absolute(PATCH_DIR)
	for f in DirAccess.get_files_at(PATCH_DIR): DirAccess.remove_absolute(PATCH_DIR.path_join(f))
	_save_state("", [])

func _save_state(version: String, revoked = null) -> void:
	var st := ConfigFile.new()
	st.load(STATE_PATH)
	st.set_value("patch", "applied_version", version)
	st.set_value("patch", "applied_base", base_version if version != "" else "")
	if revoked != null: st.set_value("patch", "revoked", revoked)
	st.save(STATE_PATH)

## -1 / 0 / 1 for dotted numeric versions ("" counts as 0).
static func cmp(a: String, b: String) -> int:
	var pa := a.split("."); var pb := b.split(".")
	for i in max(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y: return 1 if x > y else -1
	return 0

## Called from the main menu. Quietly does nothing when offline / up to date.
func check_for_updates() -> void:
	if _api_url() == "" or OS.has_feature("editor") or platform() == "" or _http: return
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	if req.request(_api_url() + "/ota/manifest") != OK:
		req.queue_free(); return
	var res: Array = await req.request_completed
	req.queue_free()
	if res[1] != 200: return
	var m = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not m is Dictionary: return

	var revoked: Array = m.get("revoke", [])
	if applied != "" and applied in revoked:
		_wipe()  # bad patch: back to base on next launch
		applied = ""
	var patch = m.get("patch")
	if patch is Dictionary and str(patch.get("base_version", "")) == base_version \
			and cmp(str(patch["patch_version"]), max_version()) > 0 \
			and not str(patch["patch_version"]) in revoked \
			and patch.get("urls", {}).has(platform()):
		_download(str(patch["patch_version"]), patch["urls"][platform()], str(patch["sha256"][platform()]))
	elif cmp(str(m.get("latest_full_version", "0")), base_version) > 0:
		full_update_available.emit(str(m.get("full_download_url", "")))

func max_version() -> String:
	return applied if cmp(applied, base_version) > 0 else base_version

func _download(version: String, url: String, sha: String) -> void:
	_show_overlay("Downloading update %s" % version)
	DirAccess.make_dir_recursive_absolute(PATCH_DIR)
	var part := PATCH_DIR.path_join("patch-%s.pck.part" % version)
	_http = HTTPRequest.new()
	_http.download_file = part
	_http.timeout = 120.0
	add_child(_http)
	set_process(true)
	_http.request(url)
	var res: Array = await _http.request_completed
	set_process(false)
	_http.queue_free()
	_http = null
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		DirAccess.remove_absolute(part)
		_finish("Update failed. We'll try again next time.", false)
		return
	if FileAccess.get_sha256(part) != sha.to_lower():
		DirAccess.remove_absolute(part)
		_finish("Update was corrupted. We'll try again next time.", false)
		return
	# Keep only the new patch.
	for f in DirAccess.get_files_at(PATCH_DIR):
		if not f.ends_with(".part"): DirAccess.remove_absolute(PATCH_DIR.path_join(f))
	DirAccess.rename_absolute(part, PATCH_DIR.path_join("patch-%s.pck" % version))
	_save_state(version)
	update_ready.emit(version)
	_finish("Update %s is ready." % version, true)

func _process(_d: float) -> void:
	if _http and _bar and _http.get_body_size() > 0:
		_bar.value = 100.0 * _http.get_downloaded_bytes() / _http.get_body_size()
		_status.text = "%.1f / %.1f MB" % [_http.get_downloaded_bytes() / 1048576.0, _http.get_body_size() / 1048576.0]

# ---------------------------------------------------------------- overlay

func _show_overlay(title: String) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.theme = load("res://theme/main_theme.tres")
	box.custom_minimum_size = Vector2(700, 0)
	box.position = Vector2(610, 420)
	box.add_theme_constant_override("separation", 20)
	_overlay.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Globals.C_AMBER)
	box.add_child(t)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(700, 30)
	box.add_child(_bar)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 28)
	box.add_child(_status)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 20)
	box.add_child(_buttons)

func _finish(msg: String, ok: bool) -> void:
	_status.text = msg
	_bar.value = 100.0 if ok else 0.0
	if ok:
		_add_button("RESTART NOW", restart)
		_add_button("LATER", _close)
	else:
		_add_button("OK", _close)

func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 32)
	b.pressed.connect(cb)
	_buttons.add_child(b)
	if _buttons.get_child_count() == 1: b.grab_focus()

func _close() -> void:
	if _overlay: _overlay.queue_free()
	_overlay = null

func restart() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
		return
	OS.set_restart_on_exit(true)
	get_tree().quit()
