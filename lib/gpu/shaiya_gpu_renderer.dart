import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math_64.dart' as v;

import '../core/formats.dart';
import 'frustum_culling.dart';

final class GpuWorldInstance {
  final String meshKey;
  final v.Matrix4 transform;

  const GpuWorldInstance({
    required this.meshKey,
    required this.transform,
  });
}

final class GpuFrameConfig {
  final v.Matrix4 viewProjection;
  final v.Matrix4 inverseViewProjection;
  final v.Vector3 cameraPosition;
  final v.Vector3 sunDirection;
  final v.Vector4 cloudColor;
  final v.Vector4 skyColor;
  final double timeSeconds;
  final double cloudDensity;

  const GpuFrameConfig({
    required this.viewProjection,
    required this.inverseViewProjection,
    required this.cameraPosition,
    required this.sunDirection,
    required this.cloudColor,
    required this.skyColor,
    required this.timeSeconds,
    this.cloudDensity = 1,
  });
}

final class _GpuMesh {
  final String key;
  final gpu.DeviceBuffer vertexBuffer;
  final gpu.DeviceBuffer indexBuffer;
  final gpu.BufferView vertices;
  final gpu.BufferView indices;
  final int indexCount;
  final RenderAabb localBounds;

  gpu.DeviceBuffer? instanceBuffer;
  int instanceCapacity = 0;

  _GpuMesh({
    required this.key,
    required this.vertexBuffer,
    required this.indexBuffer,
    required this.vertices,
    required this.indices,
    required this.indexCount,
    required this.localBounds,
  });
}

/// Flutter GPU / Impeller world renderer.
///
/// Static Shaiya geometry is uploaded exactly once per unique model. Every
/// frame only the visible transforms are streamed to an instance-rate vertex
/// buffer, so hundreds of repeated trees/columns share one indexed draw call.
final class ShaiyaGpuRenderer {
  static const String shaderAsset =
      'build/shaderbundles/shaiya_gpu.shaderbundle';

  final gpu.GpuContext context;
  final Map<String, _GpuMesh> _meshes = <String, _GpuMesh>{};

  gpu.ShaderLibrary? _library;
  gpu.RenderPipeline? _meshPipeline;
  gpu.RenderPipeline? _cloudPipeline;
  gpu.RenderPipeline? _cloudCompositePipeline;

  late final gpu.HostBuffer _uniforms;
  gpu.DeviceBuffer? _fullscreenVertices;
  gpu.BufferView? _fullscreenView;

  gpu.GpuImageSurface? _surface;
  gpu.Texture? _sceneColor;
  gpu.Texture? _depthMirror;
  gpu.Texture? _depthStencil;
  gpu.Texture? _cloudColor;

  int _width = 0;
  int _height = 0;
  double _cloudScale = .5;

  ShaiyaGpuRenderer({gpu.GpuContext? context})
      : context = context ?? gpu.gpuContext;

  bool get initialized => _meshPipeline != null;

  Future<void> initialize() async {
    if (initialized) return;

    final library = await gpu.ShaderLibrary.fromAsset(shaderAsset);
    if (library == null) {
      throw StateError('No se pudo cargar $shaderAsset.');
    }

    final meshVertex = library['ShaiyaMeshVertex'];
    final meshFragment = library['ShaiyaMeshFragment'];
    final cloudVertex = library['ShaiyaCloudVertex'];
    final cloudFragment = library['ShaiyaCloudFragment'];
    final compositeVertex = library['ShaiyaCloudCompositeVertex'];
    final compositeFragment = library['ShaiyaCloudCompositeFragment'];

    if (meshVertex == null ||
        meshFragment == null ||
        cloudVertex == null ||
        cloudFragment == null ||
        compositeVertex == null ||
        compositeFragment == null) {
      throw StateError('El shader bundle de Shaiya está incompleto.');
    }

    _library = library;
    _meshPipeline = context.createRenderPipeline(
      meshVertex,
      meshFragment,
      vertexLayout: const gpu.VertexLayout(
        buffers: <gpu.VertexBuffer>[
          gpu.VertexBuffer(
            strideInBytes: 32,
            attributes: <gpu.VertexAttribute>[
              gpu.VertexAttribute(
                name: 'position',
                format: gpu.VertexFormat.float32x3,
              ),
              gpu.VertexAttribute(
                name: 'normal',
                format: gpu.VertexFormat.float32x3,
                offsetInBytes: 12,
              ),
              gpu.VertexAttribute(
                name: 'texture_coords',
                format: gpu.VertexFormat.float32x2,
                offsetInBytes: 24,
              ),
            ],
          ),
          gpu.VertexBuffer(
            strideInBytes: 64,
            stepMode: gpu.VertexStepMode.instance,
            attributes: <gpu.VertexAttribute>[
              gpu.VertexAttribute(
                name: 'instance_m0',
                format: gpu.VertexFormat.float32x4,
              ),
              gpu.VertexAttribute(
                name: 'instance_m1',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 16,
              ),
              gpu.VertexAttribute(
                name: 'instance_m2',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 32,
              ),
              gpu.VertexAttribute(
                name: 'instance_m3',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 48,
              ),
            ],
          ),
        ],
      ),
    );

    const fullscreenLayout = gpu.VertexLayout(
      buffers: <gpu.VertexBuffer>[
        gpu.VertexBuffer(
          strideInBytes: 8,
          attributes: <gpu.VertexAttribute>[
            gpu.VertexAttribute(
              name: 'position',
              format: gpu.VertexFormat.float32x2,
            ),
          ],
        ),
      ],
    );

    _cloudPipeline = context.createRenderPipeline(
      cloudVertex,
      cloudFragment,
      vertexLayout: fullscreenLayout,
    );
    _cloudCompositePipeline = context.createRenderPipeline(
      compositeVertex,
      compositeFragment,
      vertexLayout: fullscreenLayout,
    );

    _uniforms = context.createHostBuffer(blockLengthInBytes: 64 * 1024);

    final fullscreen = Float32List.fromList(<double>[
      -1, -1,
      3, -1,
      -1, 3,
    ]);
    _fullscreenVertices =
        context.createDeviceBufferWithCopy(fullscreen.buffer.asByteData());
    _fullscreenView = gpu.BufferView(
      _fullscreenVertices!,
      offsetInBytes: 0,
      lengthInBytes: fullscreen.lengthInBytes,
    );
  }

  /// Registers one unique .3DC/.3DO-derived geometry in GPU memory.
  ///
  /// Re-registering an existing key is rejected to prevent silent duplicate
  /// uploads; callers should reuse the same key for repeated world instances.
  void registerMesh(String key, MeshData mesh) {
    if (!initialized) {
      throw StateError('initialize() debe ejecutarse antes de registerMesh().');
    }
    if (_meshes.containsKey(key)) {
      throw StateError('La malla GPU "$key" ya está registrada.');
    }
    if (mesh.vertices <= 0 || mesh.indices.isEmpty) {
      throw ArgumentError.value(key, 'key', 'La malla está vacía.');
    }

    final interleaved = ByteData(mesh.vertices * 32);
    for (var i = 0; i < mesh.vertices; i++) {
      final base = i * 32;
      interleaved
        ..setFloat32(base, mesh.positions[i * 3], Endian.host)
        ..setFloat32(base + 4, mesh.positions[i * 3 + 1], Endian.host)
        ..setFloat32(base + 8, mesh.positions[i * 3 + 2], Endian.host)
        ..setFloat32(base + 12, mesh.normals[i * 3], Endian.host)
        ..setFloat32(base + 16, mesh.normals[i * 3 + 1], Endian.host)
        ..setFloat32(base + 20, mesh.normals[i * 3 + 2], Endian.host)
        ..setFloat32(base + 24, mesh.uv[i * 2], Endian.host)
        ..setFloat32(base + 28, mesh.uv[i * 2 + 1], Endian.host);
    }

    final vertexBuffer = context.createDeviceBufferWithCopy(interleaved);
    final indexBytes = mesh.indices.buffer.asByteData(
      mesh.indices.offsetInBytes,
      mesh.indices.lengthInBytes,
    );
    final indexBuffer = context.createDeviceBufferWithCopy(indexBytes);

    _meshes[key] = _GpuMesh(
      key: key,
      vertexBuffer: vertexBuffer,
      indexBuffer: indexBuffer,
      vertices: gpu.BufferView(
        vertexBuffer,
        offsetInBytes: 0,
        lengthInBytes: interleaved.lengthInBytes,
      ),
      indices: gpu.BufferView(
        indexBuffer,
        offsetInBytes: 0,
        lengthInBytes: indexBytes.lengthInBytes,
      ),
      indexCount: mesh.indices.length,
      localBounds: _meshBounds(mesh),
    );
  }

  void setCloudResolutionScale(double value) {
    _cloudScale = value.clamp(.35, .75);
    if (_width > 0 && _height > 0) {
      _allocateTargets(_width, _height);
    }
  }

  /// Records the complete world frame:
  /// geometry -> half-res raymarched clouds -> hardware-blended composite.
  ///
  /// The returned image is backed by the Flutter GPU surface and can be shown
  /// by the current compatibility UI while the engine migrates toward a
  /// dedicated native surface path.
  ui.Image render({
    required int width,
    required int height,
    required GpuFrameConfig frame,
    required Iterable<GpuWorldInstance> instances,
  }) {
    if (!initialized) {
      throw StateError('ShaiyaGpuRenderer.initialize() no fue ejecutado.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('El tamaño del frame debe ser positivo.');
    }

    if (_width != width || _height != height || _surface == null) {
      _allocateTargets(width, height);
    }

    _uniforms.reset();

    final frustum = CameraFrustum.fromViewProjection(frame.viewProjection);
    final batches = <String, List<v.Matrix4>>{};

    for (final instance in instances) {
      final mesh = _meshes[instance.meshKey];
      if (mesh == null) continue;
      final worldBounds = _transformAabb(mesh.localBounds, instance.transform);
      if (!frustum.intersectsAabb(worldBounds)) continue;
      batches.putIfAbsent(instance.meshKey, () => <v.Matrix4>[])
          .add(instance.transform);
    }

    final commandBuffer = context.createCommandBuffer();
    _recordGeometryPass(commandBuffer, frame.viewProjection, batches);
    _recordCloudPass(commandBuffer, frame);

    final surfaceFrame = _surface!.acquireNextFrame();

    commandBuffer.copyTextureToTexture(
      gpu.TextureRegion(_sceneColor!),
      gpu.TextureDestinationRegion(surfaceFrame.colorTexture),
    );
    _recordCloudCompositePass(commandBuffer, surfaceFrame.colorTexture);

    surfaceFrame.present(commandBuffer);
    commandBuffer.submit();

    final image = _surface!.currentImage;
    if (image == null) {
      throw StateError('Flutter GPU no publicó la imagen renderizada.');
    }
    return image;
  }

  void _recordGeometryPass(
    gpu.CommandBuffer commandBuffer,
    v.Matrix4 viewProjection,
    Map<String, List<v.Matrix4>> batches,
  ) {
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget(
        colorAttachments: <gpu.ColorAttachment>[
          gpu.ColorAttachment(
            texture: _sceneColor!,
            clearValue: v.Vector4(.035, .065, .11, 1),
          ),
          gpu.ColorAttachment(
            texture: _depthMirror!,
            clearValue: v.Vector4(1, 0, 0, 0),
          ),
        ],
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: _depthStencil!,
          depthClearValue: 1,
          depthStoreAction: gpu.StoreAction.dontCare,
          stencilStoreAction: gpu.StoreAction.dontCare,
        ),
      ),
    );

    final pipeline = _meshPipeline!;
    pass
      ..bindPipeline(pipeline)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setCullMode(gpu.CullMode.backFace)
      ..setDepthWriteEnable(true)
      ..setDepthCompareOperation(gpu.CompareFunction.lessEqual);

    final frameInfo = pipeline.vertexShader.getUniformSlot('FrameInfo');
    pass.bindUniform(
      frameInfo,
      _uniforms.emplace(_matrixUniform(
        frameInfo,
        'view_projection',
        viewProjection,
      )),
    );

    for (final entry in batches.entries) {
      final mesh = _meshes[entry.key]!;
      final transforms = entry.value;
      if (transforms.isEmpty) continue;

      final instanceView = _uploadInstances(mesh, transforms);
      pass
        ..bindVertexBuffer(mesh.vertices, slot: 0)
        ..bindVertexBuffer(instanceView, slot: 1)
        ..bindIndexBuffer(mesh.indices, gpu.IndexType.int16)
        ..drawIndexed(mesh.indexCount, instanceCount: transforms.length);
    }
  }

  void _recordCloudPass(
    gpu.CommandBuffer commandBuffer,
    GpuFrameConfig frame,
  ) {
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: _cloudColor!,
          clearValue: v.Vector4.zero(),
        ),
      ),
    );

    final pipeline = _cloudPipeline!;
    pass
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(_fullscreenView!)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setDepthWriteEnable(false);

    final cloudFrame = pipeline.fragmentShader.getUniformSlot('CloudFrame');
    pass.bindUniform(
      cloudFrame,
      _uniforms.emplace(_cloudUniforms(cloudFrame, frame)),
    );
    pass.bindTexture(
      pipeline.fragmentShader.getUniformSlot('scene_depth'),
      _depthMirror!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
      ),
    );
    pass.draw(3);
  }

  void _recordCloudCompositePass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture finalColor,
  ) {
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: finalColor,
          loadAction: gpu.LoadAction.load,
          storeAction: gpu.StoreAction.store,
        ),
      ),
    );

    final pipeline = _cloudCompositePipeline!;
    pass
      ..bindPipeline(pipeline)
      ..bindVertexBuffer(_fullscreenView!)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setDepthWriteEnable(false)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(gpu.ColorBlendEquation(
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ));

    pass.bindTexture(
      pipeline.fragmentShader.getUniformSlot('cloud_color'),
      _cloudColor!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
      ),
    );
    pass.draw(3);
  }

  gpu.BufferView _uploadInstances(
    _GpuMesh mesh,
    List<v.Matrix4> transforms,
  ) {
    final requiredBytes = transforms.length * 64;
    if (mesh.instanceBuffer == null ||
        mesh.instanceCapacity < transforms.length) {
      var capacity = 1;
      while (capacity < transforms.length) {
        capacity <<= 1;
      }
      mesh.instanceBuffer =
          context.createDeviceBuffer(gpu.StorageMode.hostVisible, capacity * 64);
      mesh.instanceCapacity = capacity;
    }

    final data = ByteData(requiredBytes);
    var offset = 0;
    for (final transform in transforms) {
      final storage = transform.storage;
      for (var i = 0; i < 16; i++) {
        data.setFloat32(offset, storage[i], Endian.host);
        offset += 4;
      }
    }

    final buffer = mesh.instanceBuffer!;
    if (!buffer.overwrite(data)) {
      throw StateError('Falló la actualización del instance buffer ${mesh.key}.');
    }
    buffer.flush(offsetInBytes: 0, lengthInBytes: requiredBytes);

    return gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: requiredBytes,
    );
  }

  void _allocateTargets(int width, int height) {
    _width = width;
    _height = height;

    if (_surface == null) {
      _surface = context.createImageSurface(width, height);
    } else {
      _surface!.resize(width, height);
    }

    final colorFormat = context.defaultColorFormat;
    final depthFormat = context.defaultDepthStencilFormat;
    if (depthFormat == gpu.PixelFormat.unknown) {
      throw StateError('La GPU no expone un formato depth+stencil compatible.');
    }

    _sceneColor = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: colorFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _depthMirror = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r32Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _depthStencil = context.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: depthFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: false,
    );

    final cloudWidth = _maxInt(1, (width * _cloudScale).round());
    final cloudHeight = _maxInt(1, (height * _cloudScale).round());
    _cloudColor = context.createTexture(
      gpu.StorageMode.devicePrivate,
      cloudWidth,
      cloudHeight,
      format: colorFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
  }

  ByteData _matrixUniform(
    gpu.UniformSlot slot,
    String member,
    v.Matrix4 matrix,
  ) {
    final size = slot.sizeInBytes;
    final offset = slot.getMemberOffsetInBytes(member);
    if (size == null || offset == null) {
      throw StateError('Uniform $member no existe en ${slot.uniformName}.');
    }
    final data = ByteData(size);
    final storage = matrix.storage;
    for (var i = 0; i < 16; i++) {
      data.setFloat32(offset + i * 4, storage[i], Endian.host);
    }
    return data;
  }

  ByteData _cloudUniforms(
    gpu.UniformSlot slot,
    GpuFrameConfig frame,
  ) {
    final size = slot.sizeInBytes;
    if (size == null) {
      throw StateError('No se pudo reflejar CloudFrame.');
    }
    final data = ByteData(size);

    void matrix(String name, v.Matrix4 value) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) throw StateError('CloudFrame.$name no existe.');
      for (var i = 0; i < 16; i++) {
        data.setFloat32(offset + i * 4, value.storage[i], Endian.host);
      }
    }

    void vector(String name, v.Vector4 value) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) throw StateError('CloudFrame.$name no existe.');
      data
        ..setFloat32(offset, value.x, Endian.host)
        ..setFloat32(offset + 4, value.y, Endian.host)
        ..setFloat32(offset + 8, value.z, Endian.host)
        ..setFloat32(offset + 12, value.w, Endian.host);
    }

    matrix('uInverseViewProjection', frame.inverseViewProjection);
    vector(
      'uCameraPosition',
      v.Vector4(
        frame.cameraPosition.x,
        frame.cameraPosition.y,
        frame.cameraPosition.z,
        1,
      ),
    );
    vector(
      'uSize',
      v.Vector4(
        _width.toDouble(),
        _height.toDouble(),
        _cloudColor!.width.toDouble(),
        _cloudColor!.height.toDouble(),
      ),
    );
    vector('uTime', v.Vector4(frame.timeSeconds, _cloudScale, 0, 0));
    vector('uCloudColor', frame.cloudColor);
    vector('uSkyColor', frame.skyColor);
    vector(
      'uSunDirectionDensity',
      v.Vector4(
        frame.sunDirection.x,
        frame.sunDirection.y,
        frame.sunDirection.z,
        frame.cloudDensity,
      ),
    );
    return data;
  }
}

RenderAabb _meshBounds(MeshData mesh) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var maxZ = -double.infinity;

  for (var i = 0; i < mesh.positions.length; i += 3) {
    final x = mesh.positions[i];
    final y = mesh.positions[i + 1];
    final z = mesh.positions[i + 2];
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  return RenderAabb(
    v.Vector3(minX, minY, minZ),
    v.Vector3(maxX, maxY, maxZ),
  );
}

RenderAabb _transformAabb(RenderAabb box, v.Matrix4 transform) {
  final corners = <v.Vector3>[
    v.Vector3(box.min.x, box.min.y, box.min.z),
    v.Vector3(box.max.x, box.min.y, box.min.z),
    v.Vector3(box.min.x, box.max.y, box.min.z),
    v.Vector3(box.max.x, box.max.y, box.min.z),
    v.Vector3(box.min.x, box.min.y, box.max.z),
    v.Vector3(box.max.x, box.min.y, box.max.z),
    v.Vector3(box.min.x, box.max.y, box.max.z),
    v.Vector3(box.max.x, box.max.y, box.max.z),
  ];

  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var maxZ = -double.infinity;

  for (final corner in corners) {
    transform.transform3(corner);
    if (corner.x < minX) minX = corner.x;
    if (corner.y < minY) minY = corner.y;
    if (corner.z < minZ) minZ = corner.z;
    if (corner.x > maxX) maxX = corner.x;
    if (corner.y > maxY) maxY = corner.y;
    if (corner.z > maxZ) maxZ = corner.z;
  }

  return RenderAabb(
    v.Vector3(minX, minY, minZ),
    v.Vector3(maxX, maxY, maxZ),
  );
}

int _maxInt(int a, int b) => a > b ? a : b;
