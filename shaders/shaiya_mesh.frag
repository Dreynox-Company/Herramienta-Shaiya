in vec3 v_normal;
in vec2 v_uv;

out vec4 frag_color;
out vec4 frag_linear_depth;

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

  // Flutter GPU currently exposes depth+stencil attachments as render
  // attachments but not a portable sampled depth-only format. Mirror the
  // hardware depth into an MRT color attachment so the half-resolution cloud
  // pass can reject covered pixels before raymarching.
  frag_linear_depth = vec4(gl_FragCoord.zzz, 1.0);
}
