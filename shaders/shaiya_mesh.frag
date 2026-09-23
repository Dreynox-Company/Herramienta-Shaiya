#version 460 core

in vec3 v_normal;
in vec2 v_uv;

layout(location = 0) out vec4 frag_color;
layout(location = 1) out float frag_linear_depth;

void main() {
  vec3 normal = normalize(v_normal);
  vec3 light_dir = normalize(vec3(0.35, 0.82, 0.44));
  float diffuse = max(dot(normal, light_dir), 0.0);
  float ambient = 0.38;

  // Temporary physically coherent material fallback while original Shaiya
  // texture sampling is migrated from the legacy renderer into this pipeline.
  vec3 base = mix(
    vec3(0.38, 0.46, 0.32),
    vec3(0.62, 0.70, 0.54),
    clamp(v_uv.y, 0.0, 1.0)
  );

  frag_color = vec4(base * (ambient + diffuse * 0.72), 1.0);

  // Flutter GPU depth/stencil textures are render attachments but a portable
  // sampled depth-only format is not exposed on every target. Mirror hardware
  // depth into an R32F MRT attachment for the half-resolution cloud pass.
  frag_linear_depth = gl_FragCoord.z;
}
