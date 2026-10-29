shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D painted_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform float face_material = 0.0;
uniform float power = 0.0;
void fragment() {
    vec3 paint = use_texture ? texture(painted_texture, UV).rgb : vec3(1.0);
    ALBEDO = base_color.rgb * paint;
    ROUGHNESS = 1.0;
    float rim = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
    EMISSION = ALBEDO*(0.045+face_material*0.07+rim*(0.08+power*0.12));
}
void light() {
    float angle = dot(NORMAL,LIGHT);
    float band = angle>0.42 ? 1.0 : (angle>-0.04 ? 0.73 : 0.38);
    band = mix(band,0.86+0.14*max(angle,0.0),face_material*0.55);
    // Godot's LIGHT_COLOR includes PI. Normalize it so multiple preview/arena
    // lights preserve the shadow bands instead of bleaching the whole model.
    DIFFUSE_LIGHT += ALBEDO*LIGHT_COLOR*ATTENUATION*band/PI;
}
