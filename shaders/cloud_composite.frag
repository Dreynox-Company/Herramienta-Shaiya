#version 460 core

uniform sampler2D cloud_color;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  // cloud_color is premultiplied in the raymarch pass. Hardware blending uses
  // ONE / ONE_MINUS_SRC_ALPHA when this result is composited over the scene.
  frag_color = texture(cloud_color, v_uv);
}
