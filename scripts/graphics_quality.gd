extends RefCounted
class_name GraphicsQualityConfig

## Graphics quality for low-end hardware (old i3/i5, old Ryzen, integrated GPUs).
##
## Quality is three independent options, so a player can mix them in Settings:
##
##   msaa       2D anti-aliasing: off / 2x / 4x. Only affects curved edges (plot curves,
##              splines); panel outlines and text are analytic shader edges.
##   blur       How glass panels blur what is behind them:
##                Live  -- menus, dialogs and the top bar blur the live screen (a copy of
##                         the framebuffer per draw); node panels sample the background.
##                Baked -- every panel samples a pre-blurred, 1/4-resolution copy of the
##                         workspace background (see bg.gd); nothing copies the framebuffer.
##                Off   -- flat translucent glass, no blur at all.
##   smoothing  Restores the 9-tap gaussian on panels that read the background texture
##              (node panels, the top bar on the Dataset tab). That texture has no mip
##              levels, so without it those panels show the raw pixel-art background.
##              Only meaningful with Live blur. Measured cost is about 1% of frame time.
##
## The three presets are just named combinations of those options:
##
##   High   -- 4x MSAA, Live blur, smoothing on (the original look).
##   Medium -- MSAA off, Baked blur.
##   Low    -- MSAA off, blur Off.
##
## Selected by launch argument, same pattern as network_mode.gd:
##   godot --path . -- --graphics=low|medium|high
## An explicit argument always wins for that session and is never saved. Otherwise the
## options saved from Settings are used, and with nothing saved the preset is picked from
## the GPU: integrated / software / virtual adapters get Medium, everything else High.
## Every option can be changed while the app runs: `apply_settings()` is reversible.

enum Level {High, Medium, Low}
enum Blur {Live, Baked, Off}

const ARG_PREFIX := "--graphics="
## Key under which Settings persists the option dictionary (glob.set_var / get_var).
const SAVE_KEY := "graphics"

# Loading the shader (not assigning it to any material) is enough to make
# Godot register its `global uniform` declarations with RenderingServer.
# Without this, global_shader_parameter_set() below can silently no-op if it
# runs before any node has loaded a shader that declares this global -- which
# is exactly the case calling apply() from an early autoload's _enter_tree().
const _BlockShaderPreload := preload("res://shaders/block.gdshader")
const _ForkShaderPreload := preload("res://shaders/fork.gdshader")

# Set by apply_settings(); read by bg.gd to decide whether to bake the blurred background.
static var _bake_blur := false
static var _settings: Dictionary = {}

# The shader that keeps the live-screen (hint_screen_texture) path; when the blur is not
# Live its source is replaced with the bg-only one so no material triggers a framebuffer
# copy. The original source is remembered so Live can be restored at runtime.
const _SCREEN_SHADER_PATH := "res://shaders/block_screen.gdshader"
const _BG_ONLY_SHADER_PATH := "res://shaders/block.gdshader"
static var _screen_live_code := ""


static func bakes_blur() -> bool:
	return _bake_blur


## Level implied by the GPU when no --graphics= argument is given.
static func auto_level() -> int:
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return Level.Medium
	return Level.High


## Level named by --graphics=..., or -1 when the argument is absent or unrecognised.
static func arg_level(user_args: PackedStringArray) -> int:
	for arg in user_args:
		if arg.begins_with(ARG_PREFIX):
			match arg.substr(ARG_PREFIX.length()).to_lower():
				"low":
					return Level.Low
				"medium", "med":
					return Level.Medium
				"high":
					return Level.High
	return -1


static func resolve(user_args: PackedStringArray) -> int:
	var level := arg_level(user_args)
	return level if level >= 0 else auto_level()


## The options that make up a preset.
static func preset(level: int) -> Dictionary:
	match level:
		Level.Low:
			return {"msaa": int(Viewport.MSAA_DISABLED), "blur": int(Blur.Off), "smoothing": false}
		Level.Medium:
			return {"msaa": int(Viewport.MSAA_DISABLED), "blur": int(Blur.Baked), "smoothing": false}
	return {"msaa": int(Viewport.MSAA_4X), "blur": int(Blur.Live), "smoothing": true}


## Coerces anything (a saved variant, a half-filled dictionary) into a complete, in-range
## option dictionary. Returns {} when `raw` is not a Dictionary or is empty (the default for a
## missing save key), so callers can tell "nothing usable saved" from "saved the High preset".
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	var out := preset(Level.High)
	var msaa = raw.get("msaa", out.msaa)
	var blur = raw.get("blur", out.blur)
	if msaa is int or msaa is float:
		out.msaa = clampi(int(msaa), int(Viewport.MSAA_DISABLED), int(Viewport.MSAA_4X))
	if blur is int or blur is float:
		out.blur = clampi(int(blur), int(Blur.Live), int(Blur.Off))
	var smoothing = raw.get("smoothing", false)
	out.smoothing = smoothing is bool and smoothing
	return out


## Smoothing only does anything with Live blur; the other blur modes never use it.
static func effective(settings: Dictionary) -> Dictionary:
	var out := sanitize(settings)
	if out.is_empty():
		out = preset(Level.High)
	out.smoothing = bool(out.smoothing) and out.blur == Blur.Live
	return out


## The preset these options add up to, or -1 for a custom mix.
static func matching_level(settings: Dictionary) -> int:
	var eff := effective(settings)
	for level in [Level.High, Level.Medium, Level.Low]:
		if preset(level) == eff:
			return level
	return -1


## Options to use at startup: an explicit --graphics= wins, then what Settings saved,
## then the level implied by the GPU.
static func startup_settings(user_args: PackedStringArray, saved: Variant) -> Dictionary:
	var level := arg_level(user_args)
	if level >= 0:
		return preset(level)
	var saved_settings := sanitize(saved)
	if not saved_settings.is_empty():
		return saved_settings
	return preset(auto_level())


## The options currently applied (the High preset before anything was applied).
static func current() -> Dictionary:
	return _settings.duplicate() if not _settings.is_empty() else preset(Level.High)


## Applies the options to the running engine. Safe to call at any time and in any order:
## every option can be switched back and forth while the app runs.
static func apply_settings(settings: Dictionary) -> void:
	var s := effective(settings)
	var raw := sanitize(settings)
	var loop := Engine.get_main_loop() as SceneTree
	loop.root.msaa_2d = s.msaa as Viewport.MSAA
	_bake_blur = s.blur == Blur.Baked
	_set_screen_shader_live(s.blur == Blur.Live)
	RenderingServer.global_shader_parameter_set(&"_quality_disable_blur", s.blur == Blur.Off)
	RenderingServer.global_shader_parameter_set(&"_quality_bg_smoothing", s.smoothing)
	# Remember what the caller chose (not the effective form) so a remembered smoothing
	# choice survives a detour through Baked/Off blur.
	_settings = raw if not raw.is_empty() else s
	loop.call_group(&"graphics_bg", &"apply_quality")


## Applies a preset. Kept for callers that only know the three levels.
static func apply(level: int) -> void:
	apply_settings(preset(level))


## Every block_screen material shares one Shader resource. Swapping its source makes them
## all read the (baked) bg texture and removes the per-frame framebuffer copy; swapping the
## remembered original back restores the live-screen blur.
static func _set_screen_shader_live(live: bool) -> void:
	var screen_shader := load(_SCREEN_SHADER_PATH) as Shader
	if _screen_live_code == "":
		if live:
			return # Never swapped, so it is still the live-screen source.
		_screen_live_code = screen_shader.code
	var want := _screen_live_code if live else (load(_BG_ONLY_SHADER_PATH) as Shader).code
	if screen_shader.code != want:
		screen_shader.code = want
