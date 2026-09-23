uniform CloudFrame {
  mat4 inverse_view_projection;
  vec4 camera_time;
  vec4 resolution_scale;
  vec4 sun_density;
} cloud_frame;

uniform sampler2D scene_depth;

in vec2 v_uv;
out vec4 frag_color;

float hash31(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

float fade5(float t) {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float perlin3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = vec3(fade5(f.x), fade5(f.y), fade5(f.z));

  float n000 = dot(hash33(i + vec3(0,0,0)) * 2.0 - 1.0, f - vec3(0,0,0));
  float n100 = dot(hash33(i + vec3(1,0,0)) * 2.0 - 1.0, f - vec3(1,0,0));
  float n010 = dot(hash33(i + vec3(0,1,0)) * 2.0 - 1.0, f - vec3(0,1,0));
  float n110 = dot(hash33(i + vec3(1,1,0)) * 2.0 - 1.0, f - vec3(1,1,0));
  float n001 = dot(hash33(i + vec3(0,0,1)) * 2.0 - 1.0, f - vec3(0,0,1));
  float n101 = dot(hash33(i + vec3(1,0,1)) * 2.0 - 1.0, f - vec3(1,0,1));
  float n011 = dot(hash33(i + vec3(0,1,1)) * 2.0 - 1.0, f - vec3(0,1,1));
  float n111 = dot(hash33(i + vec3(1,1,1)) * 2.0 - 1.0, f - vec3(1,1,1));

  float nx00 = mix(n000, n100, u.x);
  float nx10 = mix(n010, n110, u.x);
  float nx01 = mix(n001, n101, u.x);
  float nx11 = mix(n011, n111, u.x);
  return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z) * 0.5 + 0.5;
}

float worley3(vec3 p) {
  vec3 cell = floor(p);
  vec3 f = fract(p);
  float nearest = 10.0;
  for (int z = -1; z <= 1; ++z) {
    for (int y = -1; y <= 1; ++y) {
      for (int x = -1; x <= 1; ++x) {
        vec3 offset = vec3(float(x), float(y), float(z));
        vec3 point = hash33(cell + offset);
        vec3 delta = offset + point - f;
        nearest = min(nearest, dot(delta, delta));
      }
    }
  }
  return 1.0 - clamp(sqrt(nearest), 0.0, 1.0);
}

float fbm(vec3 p) {
  float value = 0.0;
  float amplitude = 0.56;
  for (int octave = 0; octave < 4; ++octave) {
    value += perlin3(p) * amplitude;
    p = p * 2.03 + vec3(17.1, 9.2, 13.7);
    amplitude *= 0.48;
  }
  return value;
}

float densityAt(vec3 world) {
  float altitude = smoothstep(220.0, 300.0, world.y) *
                   (1.0 - smoothstep(570.0, 690.0, world.y));
  vec3 drift = vec3(
    cloud_frame.camera_time.w * 0.012,
    0.0,
    cloud_frame.camera_time.w * 0.007
  );
  vec3 p = world * 0.0017 + drift;
  float shape = fbm(p);
  float cells = worley3(p * 2.1);
  float hybrid = shape * 0.78 + cells * 0.22;
  return max(0.0, hybrid - 0.51) * altitude * cloud_frame.sun_density.w * 2.25;
}

vec3 reconstructFarPoint(vec2 uv) {
  vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
  vec4 world = cloud_frame.inverse_view_projection * clip;
  return world.xyz / max(abs(world.w), 1e-5);
}

void main() {
  // Half-res pass: resolution_scale.z is 0.5 on Windows/desktop and can be
  // lowered on thermal-constrained Android devices.
  vec2 full_uv = v_uv;
  float scene_z = texture(scene_depth, full_uv).r;
  if (scene_z < 0.9994) {
    frag_color = vec4(0.0);
    return;
  }

  vec3 camera = cloud_frame.camera_time.xyz;
  vec3 far_point = reconstructFarPoint(full_uv);
  vec3 ray = normalize(far_point - camera);

  float t = 80.0;
  float transmittance = 1.0;
  vec3 radiance = vec3(0.0);
  vec3 sun_dir = normalize(cloud_frame.sun_density.xyz);

  const int steps = 28;
  const float step_length = 28.0;
  for (int i = 0; i < steps; ++i) {
    vec3 sample_pos = camera + ray * t;
    float density = densityAt(sample_pos);
    if (density > 0.002) {
      float shadow_probe = densityAt(sample_pos + sun_dir * 54.0);
      float light = mix(1.0, 0.48, clamp(shadow_probe * 1.8, 0.0, 1.0));
      float alpha = 1.0 - exp(-density * 0.82);
      vec3 cloud_color = mix(
        vec3(0.48, 0.56, 0.69),
        vec3(1.0, 0.97, 0.91),
        light
      );
      radiance += transmittance * alpha * cloud_color;
      transmittance *= 1.0 - alpha;
      if (transmittance < 0.035) break;
    }
    t += step_length;
  }

  float alpha = 1.0 - transmittance;
  frag_color = vec4(radiance, alpha);
}
