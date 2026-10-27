extends Node
## Online leaderboard client (breakout-api Cloudflare Worker).
## Guest account is created on first use. Clear times go through an offline queue,
## so a run finished without network is sent next time the game is online.

signal handle_changed(handle: String)

const AUTH_FILE := "user://lb_auth.json"
const QUEUE_FILE := "user://lb_queue.json"
const QUEUE_MAX := 20
const TIMEOUT := 12.0

var api_url: String = ProjectSettings.get_setting("breakout/api_url", "")
var token := ""
var handle := ""
var _nonce := {}  # level -> nonce for the attempt in progress
var _queue: Array = []
var _flushing := false

func online() -> bool:
	return api_url != ""

func _ready() -> void:
	var f := FileAccess.open(AUTH_FILE, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if data is Dictionary and data.get("api", "") == api_url:
		token = data.get("token", "")
		handle = data.get("handle", "")
	f = FileAccess.open(QUEUE_FILE, FileAccess.READ)
	data = JSON.parse_string(f.get_as_text()) if f else null
	if data is Array: _queue = data
	if online(): flush()

# ---------------------------------------------------------------- HTTP

## Returns {ok, status, json}. Never throws; network errors give ok=false, status=0.
func _request(method: int, path: String, body = null, with_auth := true) -> Dictionary:
	if not online(): return {"ok": false, "status": 0, "json": null}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if with_auth and token != "": headers.append("Authorization: Bearer " + token)
	var err := http.request(api_url + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "json": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var status: int = res[1]
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"ok": status >= 200 and status < 300, "status": status, "json": parsed}

## Like _request, but makes a guest account first and retries once on 401.
func _authed(method: int, path: String, body = null) -> Dictionary:
	if token == "" and not await _guest(): return {"ok": false, "status": 0, "json": null}
	var r := await _request(method, path, body)
	if r["status"] == 401:
		token = ""
		if not await _guest(): return r
		r = await _request(method, path, body)
	return r

func _guest() -> bool:
	var r := await _request(HTTPClient.METHOD_POST, "/auth/guest", {}, false)
	if not r["ok"]: return false
	token = r["json"]["token"]
	handle = r["json"]["account"]["handle"]
	_save_auth()
	return true

func _save_auth() -> void:
	var f := FileAccess.open(AUTH_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"api": api_url, "token": token, "handle": handle}))

# ---------------------------------------------------------------- API

## Call when a campaign level starts. Fire and forget.
func start(level: int) -> void:
	_nonce.erase(level)
	var r := await _authed(HTTPClient.METHOD_POST, "/runs/start", {"level": level})
	if r["ok"]: _nonce[level] = r["json"]["nonce"]

## Call when the level is cleared.
func submit(level: int, seconds: float, score := 0) -> void:
	if not _nonce.has(level): return  # no ticket (offline at start): can't be verified
	_queue.append({
		"client_run_id": "%d-%d-%d" % [level, Time.get_unix_time_from_system(), randi() % 1000000],
		"nonce": _nonce[level],
		"level": level,
		"time_ms": int(seconds * 1000.0),
		"score": score,
		"skin": Globals.SKINS[Globals.skin_index]["name"],
		"build_version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
	})
	_nonce.erase(level)
	while _queue.size() > QUEUE_MAX: _queue.pop_front()
	_save_queue()
	flush()

## Sends queued runs in order; stops at the first one that should be retried later.
func flush() -> void:
	if _flushing or not online(): return
	_flushing = true
	while not _queue.is_empty():
		var r := await _authed(HTTPClient.METHOD_POST, "/runs", _queue[0])
		var retry: bool = r["status"] == 0 or r["status"] == 429 or r["status"] >= 500
		if retry: break
		_queue.pop_front()  # accepted, or rejected for good (bad nonce, impossible time...)
		_save_queue()
	_flushing = false

func _save_queue() -> void:
	var f := FileAccess.open(QUEUE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(_queue))

## {ok, total, offset, entries:[{rank, handle, time_ms, score}], me:{handle, rank, best_time_ms}|null}
## period: "all" | "week" | "day". q: part of a name (ranks stay global).
func board(level: int, limit := 10, offset := 0, period := "all", q := "") -> Dictionary:
	var path := "/boards/%d?limit=%d&offset=%d&period=%s" % [level, limit, offset, period]
	if q != "": path += "&q=" + q.uri_encode()
	# Viewing never creates an account; the token (if any) only adds "me".
	var r := await _request(HTTPClient.METHOD_GET, path)
	if r["status"] == 401:
		token = ""
		r = await _request(HTTPClient.METHOD_GET, path)
	if not r["ok"] or not r["json"] is Dictionary: return {"ok": false}
	var d: Dictionary = r["json"]
	d["ok"] = true
	return d

## Returns "" on success or an error message.
func set_handle(new_handle: String) -> String:
	var r := await _authed(HTTPClient.METHOD_PATCH, "/me", {"handle": new_handle})
	if r["ok"]:
		handle = r["json"]["account"]["handle"]
		_save_auth()
		handle_changed.emit(handle)
		return ""
	if r["json"] is Dictionary and r["json"].has("error"): return r["json"]["error"]["message"]
	return "Offline"
