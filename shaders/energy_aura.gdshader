shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 energy_color : source_color = vec4(0.2,0.7,1.0,1.0);
uniform float strength = 1.0;
void fragment() {
    float taper = pow(max(0.0,1.0-abs(UV.x*2.0-1.0)),1.4);
    float fire = 0.72+0.28*sin(UV.y*21.0-TIME*11.0+sin(UV.y*7.0+TIME*3.0));
    ALBEDO = energy_color.rgb*1.5;
    ALPHA = clamp(taper*(1.0-UV.y)*fire*strength*0.50,0.0,0.8);
}
