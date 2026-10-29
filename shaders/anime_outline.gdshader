shader_type spatial;
render_mode unshaded, cull_front;
uniform float width = 0.006;
void vertex() { VERTEX += NORMAL*width; }
void fragment() { ALBEDO = vec3(0.012,0.016,0.032); }
