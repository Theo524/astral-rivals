shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform vec4 base_color : source_color = vec4(0.2, 0.5, 0.9, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
void fragment() {
    ALBEDO = base_color.rgb;
    ROUGHNESS = 0.82;
    SPECULAR = 0.18;
    float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    EMISSION = base_color.rgb * rim * rim_strength;
}
