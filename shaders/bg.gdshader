shader_type canvas_item;
// Bottom-most, fully opaque backdrop: overwrite instead of blending with the (cleared) target.
render_mode blend_disabled;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
