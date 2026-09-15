extends RefCounted
## Versioned, checksummed, atomic local saves. No user-supplied paths accepted.

const VERSION = 1
const MAX_BYTES = 64 * 1024 * 1024

static func slot_path(slot: String) -> String:
	if slot.is_empty() or slot.length() > 48:
		return ""
	for ch in slot:
		if not (ch.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-"):
			return ""
	return "user://saves/" + slot + ".json"

static func write_save(slot: String, payload: Dictionary) -> Dictionary:
	var path = slot_path(slot)
	if path.is_empty():
		return {"ok": false, "error": "无效存档名称"}
	DirAccess.make_dir_recursive_absolute("user://saves")
	var body = JSON.stringify(payload)
	if body.length() > MAX_BYTES:
		return {"ok": false, "error": "存档过大"}
	var envelope = {"version": VERSION, "sha256": body.sha256_text(), "payload": body}
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入存档目录"}
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return {"ok": false, "error": "写入存档失败"}
	# Windows rename replacement is not uniformly supported; retain recoverable backup.
	var backup = path + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path, backup) != OK:
			return {"ok": false, "error": "无法备份旧存档"}
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return {"ok": false, "error": "无法完成存档写入"}
	return {"ok": true}

static func read_save(slot: String) -> Dictionary:
	var path = slot_path(slot)
	if path.is_empty():
		return {"ok": false, "error": "无效存档名称"}
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		path += ".bak"
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "没有找到存档"}
	if file.get_length() > MAX_BYTES:
		return {"ok": false, "error": "存档大小超限"}
	var envelope = JSON.parse_string(file.get_as_text())
	if not envelope is Dictionary or int(envelope.get("version", 0)) != VERSION:
		return {"ok": false, "error": "不支持的存档格式"}
	var body = envelope.get("payload", "")
	if not body is String or body.sha256_text() != envelope.get("sha256", ""):
		return {"ok": false, "error": "存档校验失败，原文件已保留"}
	var data = JSON.parse_string(body)
	if not data is Dictionary or not data.get("state") is Dictionary:
		return {"ok": false, "error": "存档内容无效"}
	return {"ok": true, "data": data}
