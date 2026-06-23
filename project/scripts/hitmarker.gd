extends Control

var hit_timer: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_hit() -> void:
	hit_timer = 0.15
	queue_redraw()

func _process(delta: float) -> void:
	if hit_timer > 0.0:
		hit_timer -= delta
		if hit_timer <= 0.0:
			hit_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if hit_timer <= 0.0:
		return
	
	var center := size / 2.0
	var alpha := hit_timer / 0.15
	var color := Color(1.0, 1.0, 1.0, alpha)
	var length := 7.0
	var gap := 6.0
	var width := 1.8
	
	# Top-Left diagonal
	draw_line(center + Vector2(-gap, -gap), center + Vector2(-gap - length, -gap - length), color, width, true)
	# Top-Right diagonal
	draw_line(center + Vector2(gap, -gap), center + Vector2(gap + length, -gap - length), color, width, true)
	# Bottom-Left diagonal
	draw_line(center + Vector2(-gap, gap), center + Vector2(-gap - length, gap + length), color, width, true)
	# Bottom-Right diagonal
	draw_line(center + Vector2(gap, gap), center + Vector2(gap + length, gap + length), color, width, true)
