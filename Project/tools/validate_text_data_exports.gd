extends SceneTree


const TEXT_TABLES: Array[String] = [
	"res://data/cards.txt",
	"res://data/talents.txt",
	"res://data/opponents.txt",
	"res://data/Cards/Cards_Visual.txt",
	"res://data/event/Events_Visual.txt",
]


func _initialize() -> void:
	var errors: Array[String] = []
	for path in TEXT_TABLES:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			errors.append("%s 无法打开" % path)
			continue
		var headers: PackedStringArray = f.get_csv_line()
		var rows: int = 0
		while not f.eof_reached():
			var row: PackedStringArray = f.get_csv_line()
			if row.size() == 0:
				continue
			if String(row[0]).strip_edges().begins_with("#"):
				continue
			if String(row[0]).strip_edges() == "":
				continue
			rows += 1
		f.close()
		if headers.size() == 0:
			errors.append("%s 表头为空" % path)
		if rows == 0:
			errors.append("%s 没有可用数据行" % path)
		else:
			print("%s OK (%d rows)" % [path, rows])
	if errors.is_empty():
		quit(0)
		return
	for error in errors:
		push_error(error)
	quit(1)
