shader_type canvas_item;
#include "res://shaders/std.gdshaderinc"
render_mode world_vertex_coords;

global uniform sampler2D bg: filter_linear_mipmap_anisotropic;

// Blur-the-`bg`-texture variant (default). No screen-texture read, so no
// per-draw framebuffer copy. Shader body: block_body.gdshaderinc.
#include "res://shaders/block_body.gdshaderinc"
