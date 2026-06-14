class_name MazeGen
extends RefCounted
## Oda + koridor zindan üreticisi ("Rooms and Mazes").
## Önce odalar yerleştirilir, boş alana koridor labirenti örülür, sonra bölgeler
## kapı bağlantılarıyla birleştirilir ve fazla koridor uçları budanır.
## v_walls[x][y]: (x-1,y)-(x,y) arası dikey duvar (x: 0..w)
## h_walls[x][y]: (x,y-1)-(x,y) arası yatay duvar (y: 0..h)

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ROOM_TYPES := ["depo", "sapel", "yemekhane", "hazine", "yatakhane"]


static func generate(w: int, h: int, rng_seed: int, braid := 0.12) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var v_walls: Array = []
	for x in w + 1:
		v_walls.append(_filled(h))
	var h_walls: Array = []
	for x in w:
		h_walls.append(_filled(h + 1))

	var region := {}          # Vector2i -> bölge id
	var region_of := []       # union-find üst dizisi
	var next_region := 0

	# --- 1) odalar: çok ve geniş, başlangıç hücresini boş bırak ---
	var rooms: Array[Dictionary] = []
	var room_cells := {}
	var max_rooms: int = clampi(int(w * h / 9.0), 5, 11)
	var attempts := w * h
	while rooms.size() < max_rooms and attempts > 0:
		attempts -= 1
		var rw := rng.randi_range(2, 4)
		var rh := rng.randi_range(2, 3)
		var rx := rng.randi_range(0, w - rw)
		var ry := rng.randi_range(0, h - rh)
		var rect := Rect2i(rx, ry, rw, rh)
		if rect.grow(1).has_point(Vector2i.ZERO):
			continue  # spawn hücresi koridor kalsın
		var clash := false
		for cy in range(ry - 1, ry + rh + 1):
			for cx in range(rx - 1, rx + rw + 1):
				if room_cells.has(Vector2i(cx, cy)):
					clash = true
					break
			if clash:
				break
		if clash:
			continue
		var rid := next_region
		next_region += 1
		region_of.append(rid)
		for cx in range(rx, rx + rw):
			for cy in range(ry, ry + rh):
				var c := Vector2i(cx, cy)
				region[c] = rid
				room_cells[c] = true
				if cx + 1 < rx + rw:
					v_walls[cx + 1][cy] = false
				if cy + 1 < ry + rh:
					h_walls[cx][cy + 1] = false
		rooms.append({"rect": rect, "type": ROOM_TYPES[rng.randi() % ROOM_TYPES.size()]})

	# --- 2) boş hücrelere koridor labirenti ör (her bağımsız parça = bölge) ---
	for sx in w:
		for sy in h:
			var start := Vector2i(sx, sy)
			if region.has(start):
				continue
			var rid := next_region
			next_region += 1
			region_of.append(rid)
			var stack: Array[Vector2i] = [start]
			region[start] = rid
			while not stack.is_empty():
				var c: Vector2i = stack.back()
				var options: Array[Vector2i] = []
				for d: Vector2i in DIRS:
					var n: Vector2i = c + d
					if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h \
							and not region.has(n) and not room_cells.has(n):
						options.append(n)
				if options.is_empty():
					stack.pop_back()
					continue
				var nxt: Vector2i = options[rng.randi() % options.size()]
				_open_between(v_walls, h_walls, c, nxt)
				region[nxt] = rid
				stack.append(nxt)

	# --- 3) bölgeleri kapı bağlantılarıyla birleştir (union-find) ---
	var connectors: Array = []  # [cell_a, cell_b]
	for x in w:
		for y in h:
			var c := Vector2i(x, y)
			if not region.has(c):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if n.x < w and n.y < h and region.has(n) \
						and region[c] != region[n] and has_wall_between(v_walls, h_walls, c, n):
					connectors.append([c, n])
	_shuffle(connectors, rng)
	for pair: Array in connectors:
		var ra: int = _find(region_of, region[pair[0]])
		var rb: int = _find(region_of, region[pair[1]])
		if ra != rb:
			_open_between(v_walls, h_walls, pair[0], pair[1])
			region_of[ra] = rb  # birleştir
		elif rng.randf() < braid:
			_open_between(v_walls, h_walls, pair[0], pair[1])  # nadir döngü

	# --- 4) koridor çıkmazlarını buda (oda dışı, tek açıklıklı uçları kapat) ---
	for _pass in 2:
		for x in w:
			for y in h:
				var c := Vector2i(x, y)
				if c == Vector2i.ZERO or room_cells.has(c):
					continue
				if _wall_count(v_walls, h_walls, c, w, h) == 3 and rng.randf() < 0.6:
					for d: Vector2i in DIRS:
						var n: Vector2i = c + d
						if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h \
								and not has_wall_between(v_walls, h_walls, c, n):
							_close_between(v_walls, h_walls, c, n)
							break

	# --- 5) BFS: ulaşılabilirlik + en uzak hücre = çıkış ---
	var dist := { Vector2i.ZERO: 0 }
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var far := Vector2i.ZERO
	var far_corridor := Vector2i(-1, -1)  # oda olmayan en uzak hücre (çıkış için tercih)
	while not queue.is_empty():
		var c2: Vector2i = queue.pop_front()
		for d: Vector2i in DIRS:
			var n: Vector2i = c2 + d
			if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h \
					and not dist.has(n) and not has_wall_between(v_walls, h_walls, c2, n):
				dist[n] = dist[c2] + 1
				if dist[n] > dist[far]:
					far = n
				if not room_cells.has(n) and (far_corridor.x < 0 or dist[n] > dist[far_corridor]):
					far_corridor = n
				queue.append(n)
	# çıkış: mümkünse koridor hücresi (halkanın altı temiz kalsın).
	# Yol uzaklığı tek başına yetmez — kıvrımlı labirentte en uzak koridor
	# spawn'ın fiziksel komşusu çıkabiliyor; portal ışığı/etiketi daha ilk
	# adımda görünür. Spawn'a manhattan olarak yakın hücreleri ele.
	var min_geo := (w + h) / 4
	var far_geo := Vector2i(-1, -1)
	for c4: Vector2i in dist:
		if room_cells.has(c4) or c4.x + c4.y < min_geo:
			continue
		if far_geo.x < 0 or dist[c4] > dist[far_geo]:
			far_geo = c4
	if far_geo.x >= 0:
		far = far_geo
	elif far_corridor.x >= 0:
		far = far_corridor

	# --- 6) ulaşılabilir koridor çıkmazları (sandık adayları) ---
	var dead_ends: Array[Vector2i] = []
	for x in w:
		for y in h:
			var c3 := Vector2i(x, y)
			if c3 != Vector2i.ZERO and c3 != far and not room_cells.has(c3) \
					and dist.has(c3) and _wall_count(v_walls, h_walls, c3, w, h) >= 3:
				dead_ends.append(c3)

	return {
		"w": w, "h": h,
		"v_walls": v_walls, "h_walls": h_walls,
		"exit": far, "dist": dist, "dead_ends": dead_ends,
		"rooms": rooms, "room_cells": room_cells,
	}


# ---------- union-find ----------

static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------- duvar yardımcıları ----------

static func has_wall_between(v_walls: Array, h_walls: Array, a: Vector2i, b: Vector2i) -> bool:
	if b.x == a.x + 1:
		return v_walls[a.x + 1][a.y]
	if b.x == a.x - 1:
		return v_walls[a.x][a.y]
	if b.y == a.y + 1:
		return h_walls[a.x][a.y + 1]
	return h_walls[a.x][a.y]


static func _open_between(v_walls: Array, h_walls: Array, a: Vector2i, b: Vector2i) -> void:
	if b.x == a.x + 1:
		v_walls[a.x + 1][a.y] = false
	elif b.x == a.x - 1:
		v_walls[a.x][a.y] = false
	elif b.y == a.y + 1:
		h_walls[a.x][a.y + 1] = false
	else:
		h_walls[a.x][a.y] = false


static func _close_between(v_walls: Array, h_walls: Array, a: Vector2i, b: Vector2i) -> void:
	if b.x == a.x + 1:
		v_walls[a.x + 1][a.y] = true
	elif b.x == a.x - 1:
		v_walls[a.x][a.y] = true
	elif b.y == a.y + 1:
		h_walls[a.x][a.y + 1] = true
	else:
		h_walls[a.x][a.y] = true


static func _wall_count(v_walls: Array, h_walls: Array, c: Vector2i, w: int, h: int) -> int:
	var count := 0
	for d: Vector2i in DIRS:
		var n: Vector2i = c + d
		if n.x < 0 or n.x >= w or n.y < 0 or n.y >= h:
			count += 1
		elif has_wall_between(v_walls, h_walls, c, n):
			count += 1
	return count


static func _filled(n: int) -> Array:
	var arr := []
	for i in n:
		arr.append(true)
	return arr
