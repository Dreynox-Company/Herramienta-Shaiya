in vec3 v_normal;
in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec3 normal = normalize(v_normal);
  vec3 light_dir = normalize(vec3(0.35, 0.82, 0.44));
  float diffuse = max(dot(normal, light_dir), 0.0);
  float ambient = 0.38;
  vec3 base = mix(
    vec3(0.38, 0.46, 0.32),
    vec3(0.62, 0.70, 0.54),
    clamp(v_uv.y, 0.0, 1.0)
  );
  frag_color = vec4(base * (ambient + diffuse * 0.72), 1.0);
}
