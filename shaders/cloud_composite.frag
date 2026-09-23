uniform sampler2D cloud_color;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  // Half-resolution clouds are sampled with linear filtering and composited
  // as premultiplied alpha over the fully rendered world.
  frag_color = texture(cloud_color, v_uv);
}
