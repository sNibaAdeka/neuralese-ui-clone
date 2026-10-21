class_name BuiltinProjectCard
extends BlockComponent

signal open_requested(project_id: StringName)

const FALLBACK_TEXTURE := preload("res://neuralese.png")

@onready var surface: ColorRect = $Surface
@onready var preview: TextureRect = $Surface/Margin/Row/PreviewFrame/PreviewMargin/Preview
@onready var preview_frame: PanelContainer = $Surface/Margin/Row/PreviewFrame
@onready var emoji_badge: PanelContainer = $Surface/Margin/Row/Info/Header/EmojiBadge
@onready var emoji_label: Label = $Surface/Margin/Row/Info/Header/EmojiBadge/Emoji
@onready var title_label: Label = $Surface/Margin/Row/Info/Header/Title
@onready var description_label: RichTextLabel = $Surface/Margin/Row/Info/Description
@onready var tags: HFlowContainer = $Surface/Margin/Row/Info/Tags
@onready var open_badge: PanelContainer = $Surface/Margin/Row/Info/OpenRow/OpenBadge
@onready var open_label: Label = $Surface/Margin/Row/Info/OpenRow/OpenBadge/OpenLabel

var definition: Resource
var language := "ru"
var _accent := Color(0.49, 0.83, 0.61, 1.0)
var _display_outline := _accent


func configure(value: Resource, current_language: String) -> void:
	definition = value
	language = current_language
	if definition != null:
		hint = definition.id
		metadata["builtin_project_id"] = String(definition.id)
	if is_node_ready():
		_apply_definition()


func _ready() -> void:
	super()
	released.connect(_on_released)
	_apply_definition()


func _process(delta: float) -> void:
	super(delta)
	if definition == null:
		return
	var target := _accent
	if state.pressing:
		target = _accent.lightened(0.24)
	elif state.hovering:
		target = _accent.lightened(0.16)
	_display_outline = _display_outline.lerp(target, minf(1.0, delta * 12.0))
	surface.set_instance_shader_parameter("outline_color", _display_outline)


func _apply_definition() -> void:
	if definition == null or not is_node_ready():
		return
	_accent = definition.accent_color
	_display_outline = _accent
	surface.set_instance_shader_parameter("outline_color", _accent)
	preview.texture = definition.preview if definition.preview != null else FALLBACK_TEXTURE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	emoji_label.text = definition.emoji
	title_label.text = definition.localized_title(language)
	description_label.text = definition.localized_description(language)
	open_label.text = _copy("Сделать копию  →", "Make a copy  →", "Көшірме жасау  →")
	_apply_accent_style(preview_frame, _accent, Color(0.05, 0.05, 0.08, 0.52), 1)
	_apply_accent_style(
		emoji_badge, _accent, Color(_accent.r, _accent.g, _accent.b, 0.13), 1, Vector2(8, 5)
	)
	_apply_accent_style(
		open_badge, _accent, Color(_accent.r, _accent.g, _accent.b, 0.10), 1, Vector2(16, 7)
	)
	_build_tags(definition.localized_tags(language))
	tooltip_text = "%s — %s" % [title_label.text, description_label.text]


func _build_tags(values: PackedStringArray) -> void:
	for child in tags.get_children():
		child.queue_free()
	for value in values:
		var tag := Label.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.text = value
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", Color(0.86, 0.87, 0.91, 0.92))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.10)
		style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.34)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 9
		style.content_margin_right = 9
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		tag.add_theme_stylebox_override("normal", style)
		tags.add_child(tag)


func _apply_accent_style(
	target: PanelContainer,
	accent: Color,
	background: Color,
	border_width: int,
	content_padding: Vector2 = Vector2.ZERO
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(accent.r, accent.g, accent.b, 0.72)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.content_margin_left = content_padding.x
	style.content_margin_right = content_padding.x
	style.content_margin_top = content_padding.y
	style.content_margin_bottom = content_padding.y
	target.add_theme_stylebox_override("panel", style)


func _on_released() -> void:
	if definition != null:
		open_requested.emit(definition.id)


func _copy(ru: String, en: String, kz: String) -> String:
	match language:
		"en": return en
		"kz": return kz
		_: return ru
