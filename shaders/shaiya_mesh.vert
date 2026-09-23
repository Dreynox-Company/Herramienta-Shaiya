uniform FrameInfo {
  mat4 mvp;
} frame_info;

in vec3 position;
in vec3 normal;
in vec2 texture_coords;

out vec3 v_normal;
out vec2 v_uv;

void main() {
  v_normal = normal;
  v_uv = texture_coords;
  gl_Position = frame_info.mvp * vec4(position, 1.0);
}
