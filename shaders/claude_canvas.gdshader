shader_type canvas_item;
render_mode unshaded;

// Screen-space, opaque workspace surface shared by the direct background and
// cached `bg` texture. Camera motion affects only the dots, never the frame.
uniform vec4 bg_color : source_color = vec4(1.0);
uniform vec4 grid_color : source_color = vec4(0.88235, 0.89412, 0.92549, 1.0);
uniform vec4 page_color : source_color = vec4(0.96078, 0.96471, 0.98039, 1.0);
uniform vec4 wash_color : source_color = vec4(0.85882, 0.91373, 0.99216, 1.0);
uniform vec4 wash_soft_color : source_color = vec4(0.93725, 0.96078, 0.99608, 1.0);
uniform vec4 border_color : source_color = vec4(0.89412, 0.90196, 0.93333, 1.0);
uniform vec2 canvas_size = vec2(1152.0, 658.0);
uniform bool framed_workspace = false;
uniform vec4 workspace_rect = vec4(0.0);
uniform float panel_radius = 28.0;
uniform vec2 camera_offset = vec2(0.0);
uniform float grid_zoom = 1.0;
uniform float spacing = 26.0;
uniform float width = 2.6;

float rounded_rect_distance(vec2 point, vec4 rect, float radius) {
	vec2 half_size = rect.zw * 0.5;
	float safe_radius = min(max(radius, 0.0), min(half_size.x, half_size.y));
	vec2 edge = abs(point - rect.xy - half_size) - half_size + vec2(safe_radius);
	return length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - safe_radius;
}

void fragment() {
	float scale = max(grid_zoom, 0.05);
	float period = spacing * scale;
	vec2 screen_position = UV * canvas_size;
	vec2 pixel_position = screen_position - canvas_size * 0.5 + camera_offset;
	vec2 cell = mod(pixel_position + period * 0.5, period) - period * 0.5;
	float radius = max(0.7, width * 0.5 * scale);
	float aa = max(fwidth(length(cell)), 0.35);
	float dot_mask = 1.0 - smoothstep(radius - aa, radius + aa, length(cell));
	vec3 grid = mix(bg_color.rgb, grid_color.rgb, dot_mask);
	vec3 surface = grid;
	if (framed_workspace) {
		// Claude's page wash fades through 170px into the neutral page at 420px.
		vec3 wash = mix(wash_color.rgb, wash_soft_color.rgb, clamp(screen_position.y / 170.0, 0.0, 1.0));
		surface = mix(wash, page_color.rgb, clamp((screen_position.y - 170.0) / 250.0, 0.0, 1.0));
		if (workspace_rect.z > 0.0 && workspace_rect.w > 0.0) {
			float distance_to_frame = rounded_rect_distance(screen_position, workspace_rect, panel_radius);
			float edge_aa = max(fwidth(distance_to_frame), 0.35);
			float canvas_mask = 1.0 - smoothstep(-edge_aa, edge_aa, distance_to_frame);
			float border_mask = 1.0 - smoothstep(1.0 - edge_aa, 1.0 + edge_aa, distance_to_frame);
			surface = mix(surface, border_color.rgb, border_mask);
			surface = mix(surface, grid, canvas_mask);
		}
	}
	COLOR = vec4(surface, 1.0);
}
