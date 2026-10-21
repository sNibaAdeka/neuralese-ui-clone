shader_type canvas_item;

// One-shot "bake" of the workspace background into a small pre-blurred texture.
// Rendered by bg.gd into a low-res SubViewport only when the background changes;
// panels then read it with a single texture tap instead of blurring per pixel
// every frame (or copying the framebuffer). 16 bilinear taps over an 8x8 source
// footprint per output texel; the low-res upsample adds the rest of the softness.
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 acc = vec4(0.0);
	for (int y = -1; y <= 2; y++) {
		for (int x = -1; x <= 2; x++) {
			vec2 o = (vec2(float(x), float(y)) * 2.0 - vec2(1.0)) * px;
			acc += texture(TEXTURE, UV + o);
		}
	}
	COLOR = acc / 16.0;
}
