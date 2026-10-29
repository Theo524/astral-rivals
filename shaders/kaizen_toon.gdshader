shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, ambient_light_disabled;

// Kaizen's art pass is isolated from the other fighters. Broad, tinted shadow
// planes and restrained edge light keep cloth and anatomy readable in motion.
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D painted_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform vec4 shadow_tint : source_color = vec4(0.53, 0.60, 0.79, 1.0);
uniform float face_material = 0.0;
uniform float ink_detail = 0.0;
uniform float eye_detail = 0.0;
uniform float hair_material = 0.0;
uniform float power = 0.0;

void fragment() {
    vec3 paint = use_texture ? texture(painted_texture, UV).rgb : vec3(1.0);
    ALBEDO = base_color.rgb * paint;
    ROUGHNESS = 1.0;
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
    float detail = max(ink_detail, eye_detail);
    // Painted facial lines/eyes stay legible without an inflated outline hull.
    EMISSION = ALBEDO * mix(0.10 + rim * (0.06 + power * 0.08), 0.92, detail);
    EMISSION += hair_material * vec3(0.012, 0.023, 0.042) * rim * (1.0 - power * 0.65);
}

void light() {
    float ndl = dot(NORMAL, LIGHT);
    float edge = mix(0.035, 0.09, face_material);
    float lit = smoothstep(0.18 - edge, 0.18 + edge, ndl);
    vec3 shade = mix(shadow_tint.rgb * 0.78, vec3(1.0), lit);
    float detail = max(ink_detail, eye_detail);
    // LIGHT_COLOR already contains PI in Godot. Preserve the actual colour.
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shade * (1.0 - detail) / PI;
}
