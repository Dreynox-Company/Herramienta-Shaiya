#version 460 core

uniform CloudFrame {
  mat4 uInverseViewProjection;
  vec4 uCameraPosition;
  vec4 uSize;
  vec4 uTime;
  vec4 uCloudColor;
  vec4 uSkyColor;
  vec4 uSunDirectionDensity;
} cloud_frame;

uniform sampler2D scene_depth;

in vec2 v_uv;
out vec4 frag_color;

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

  float n000 = dot(hash33(i + vec3(0,0,0)) * 2.0 - 1.0, f);
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
  float sum = 0.0;
  float amplitude = 0.55;
  for (int octave = 0; octave < 4; ++octave) {
    sum += perlin3(p) * amplitude;
    p = p * 2.03 + vec3(17.1, 9.2, 13.7);
    amplitude *= 0.48;
  }
  return sum;
}

float cloudDensity(vec3 world) {
  float bottom = smoothstep(220.0, 300.0, world.y);
  float top = 1.0 - smoothstep(570.0, 690.0, world.y);
  float altitude = bottom * top;

  vec3 wind = vec3(cloud_frame.uTime.x * 0.012, 0.0,
                   cloud_frame.uTime.x * 0.007);
  vec3 p = world * 0.0017 + wind;

  float baseShape = fbm(p);
  float cells = worley3(p * 2.1);
  float erosion = mix(baseShape, cells, 0.22);
  float coverage = cloud_frame.uCloudColor.a;

  return max(0.0, erosion - mix(0.64, 0.43, coverage)) *
         altitude * cloud_frame.uSunDirectionDensity.w * 2.15;
}

vec3 farWorldPoint(vec2 uv) {
  vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
  vec4 world = cloud_frame.uInverseViewProjection * clip;
  return world.xyz / max(abs(world.w), 1e-5);
}

void main() {
  // The pass itself renders into a target sized uSize.zw (normally 0.5x
  // uSize.xy), so raymarch cost is quarter resolution while the world stays
  // at full native resolution.
  float opaqueDepth = texture(scene_depth, v_uv).r;
  if (opaqueDepth < 0.9994) {
    frag_color = vec4(0.0);
    return;
  }

  vec3 camera = cloud_frame.uCameraPosition.xyz;
  vec3 ray = normalize(farWorldPoint(v_uv) - camera);
  vec3 sunDir = normalize(cloud_frame.uSunDirectionDensity.xyz);

  float t = 70.0;
  float transmittance = 1.0;
  vec3 premultiplied = vec3(0.0);

  const int kSteps = 28;
  const float kStepLength = 29.0;

  for (int i = 0; i < kSteps; ++i) {
    vec3 p = camera + ray * t;
    float density = cloudDensity(p);

    if (density > 0.002) {
      float lightProbe = cloudDensity(p + sunDir * 56.0);
      float sunlight = mix(1.0, 0.46, clamp(lightProbe * 1.8, 0.0, 1.0));
      float sampleAlpha = 1.0 - exp(-density * 0.82);

      vec3 litCloud = mix(
        cloud_frame.uSkyColor.rgb * 0.60,
        cloud_frame.uCloudColor.rgb,
        sunlight
      );

      premultiplied += transmittance * sampleAlpha * litCloud;
      transmittance *= 1.0 - sampleAlpha;

      if (transmittance < 0.035) {
        break;
      }
    }

    t += kStepLength;
  }

  frag_color = vec4(premultiplied, 1.0 - transmittance);
}
