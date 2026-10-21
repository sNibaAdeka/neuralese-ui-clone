shader_type canvas_item;
render_mode world_vertex_coords;

// Node-only surface: keep the instance parameters used by graph selection,
// screenshots and scroll clipping, without changing the shared panel shader.
instance uniform vec4 tuning : source_color = vec4(1.0);
instance uniform vec4 outline_color : source_color = vec4(0.89, 0.90, 0.93, 1.0);
instance uniform vec2 corner_radius_width_add = vec2(0.0);
uniform vec4 header_color : source_color = vec4(1.0);
uniform vec4 body_color : source_color = vec4(1.0);
uniform float corner_radius = 24.0;
uniform float outline_width = 0.7;
uniform bool use_bg = true;
#include "res://shaders/smooth_extents.gdshaderinc"

varying vec2 world_position;
varying vec2 surface_scale;
varying vec4 node_modulate;

void vertex() {
	world_position = VERTEX;
	surface_scale = vec2(length(CANVAS_MATRIX[0].xy), length(CANVAS_MATRIX[1].xy))
		* vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
	node_modulate = COLOR;
}

void fragment() {
	vec2 size_px = vec2(1.0 / max(length(dFdx(UV)), 0.00001),
		1.0 / max(length(dFdy(UV)), 0.00001));
	vec2 half_size = size_px * 0.5;
	vec2 p = (UV - vec2(0.5)) * size_px;
	float scale_factor = min(surface_scale.x, surface_scale.y);
	float radius = min((corner_radius + corner_radius_width_add.x) * scale_factor,
		min(half_size.x, half_size.y));
	vec2 q = abs(p) - (half_size - vec2(radius));
	float distance_to_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(-1.0, 0.5, distance_to_edge);
	float line_width = (outline_width + corner_radius_width_add.y) * scale_factor;
	float outline = smoothstep(-line_width - 0.7, -line_width + 0.7, distance_to_edge);
	vec4 surface = mix(header_color, body_color, smoothstep(0.02, 0.65, UV.y));
	COLOR = mix(surface, outline_color, outline) * node_modulate;
	COLOR.a *= mask * alphamult(world_position);
}
