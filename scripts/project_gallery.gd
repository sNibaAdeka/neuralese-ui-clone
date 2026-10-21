class_name ProjectGallery
extends Control

signal project_open_requested(project_id: String)
signal project_delete_requested(project_id: String)

const GRID_HORIZONTAL_INSET := 15.0
const SCROLLBAR_RESERVE := 18.0

@onready var grid: ProjectGrid = $GalleryInset/Scroll/GridCenter/Grid
@onready var scroll: ScrollContainer = $GalleryInset/Scroll
@onready var loading_state: CenterContainer = $LoadingState
@onready var empty_state: CenterContainer = $EmptyState


func _ready() -> void:
	grid.project_open_requested.connect(project_open_requested.emit)
	grid.project_delete_requested.connect(project_delete_requested.emit)


func set_loading(loading: bool) -> void:
	loading_state.visible = loading
	if loading:
		empty_state.hide()
		scroll.hide()


func set_projects(projects: Dictionary, current_project_id: Variant) -> void:
	set_loading(false)
	var is_empty := projects.is_empty()
	empty_state.visible = is_empty
	scroll.visible = not is_empty
	await grid.set_projects(projects, str(current_project_id), str(glob.get_lang()))


func set_column_count(column_count: int) -> void:
	grid.columns = maxi(1, column_count)


func horizontal_chrome() -> float:
	return GRID_HORIZONTAL_INSET * 2.0 + SCROLLBAR_RESERVE
