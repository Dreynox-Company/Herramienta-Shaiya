#version 460 core

uniform FrameInfo {
  mat4 view_projection;
} frame_info;

in vec3 position;
in vec3 normal;
in vec2 texture_coords;

in vec4 instance_m0;
in vec4 instance_m1;
in vec4 instance_m2;
in vec4 instance_m3;

out vec3 v_normal;
out vec2 v_uv;

void main() {
  mat4 model = mat4(instance_m0, instance_m1, instance_m2, instance_m3);
  vec4 world = model * vec4(position, 1.0);
  v_normal = normalize(mat3(model) * normal);
  v_uv = texture_coords;
  gl_Position = frame_info.view_projection * world;
}
