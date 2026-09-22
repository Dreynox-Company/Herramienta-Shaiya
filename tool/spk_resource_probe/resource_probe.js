'use strict';

const CONFIG = __CONFIG__;
const hooks = new Set();
const listeners = [];
const algs = new Map();
const props = new Map();
const keys = new Map();
const seen = new Set();
let observer = null;
let active = true;
let events = 0;
let captures = 0;

function event(code, details = {}) {
  if (events++ < 250) send({kind: 'event', code, details});
}

function hex(buffer) {
  return Array.from(new Uint8Array(buffer))
      .map(x => x.toString(16).padStart(2, '0'))
      .join('');
}

function safe(pointer, length, max = 8192) {
  if (pointer.isNull() || !length || length > max) return null;
  try {
    return hex(pointer.readByteArray(length));
  } catch (_) {
    return null;
  }
}

function location(pointer) {
  const module = Process.findModuleByAddress(pointer);
  return module
      ? {module: module.name, rva: pointer.sub(module.base).toString()}
      : {module: null, address: pointer.toString()};
}

function align(value, boundary) {
  return Math.ceil(value / boundary) * boundary;
}

function authenticatedInfo(pointer) {
  try {
    if (pointer.isNull()) return null;
    const cbSize = pointer.readU32();
    const version = pointer.add(4).readU32();
    const ps = Process.pointerSize;
    // Windows x86 uses a 64-byte structure; x64 uses 88 bytes.
    if (cbSize < 56 || cbSize > 128) return null;

    let off = 8;
    const noncePtr = pointer.add(off).readPointer();
    off += ps;
    const nonceBytes = pointer.add(off).readU32();
    off += 4;
    off = align(off, ps);

    const aadPtr = pointer.add(off).readPointer();
    off += ps;
    const aadBytes = pointer.add(off).readU32();
    off += 4;
    off = align(off, ps);

    const tagPtr = pointer.add(off).readPointer();
    off += ps;
    const tagBytes = pointer.add(off).readU32();
    off += 4;
    off = align(off, ps);

    const macPtr = pointer.add(off).readPointer();
    off += ps;
    const macBytes = pointer.add(off).readU32();
    off += 4;

    const cbAAD = pointer.add(off).readU32();
    off += 4;
    // ULONGLONG keeps 8-byte alignment with the default Windows packing.
    off = align(off, 8);
    const cbData = pointer.add(off).readU64().toString();
    off += 8;
    const flags = pointer.add(off).readU32();

    if (off + 4 > cbSize) return null;
    return {
      cbSize,
      version,
      pointerSize: ps,
      targetArch: Process.arch,
      nonceHex: safe(noncePtr, nonceBytes, 256),
      nonceBytes,
      authDataHex: safe(aadPtr, aadBytes, 8192),
      authDataBytes: aadBytes,
      tagHex: safe(tagPtr, tagBytes, 256),
      tagBytes,
      macContextHex: safe(macPtr, macBytes, 512),
      macContextBytes: macBytes,
      cbAAD,
      cbData,
      flags,
    };
  } catch (_) {
    return null;
  }
}

function attach(module) {
  if (module.name.toLowerCase() !== 'bcrypt.dll') return;
  if (hooks.has(module.base.toString())) return;
  hooks.add(module.base.toString());

  const open = module.findExportByName('BCryptOpenAlgorithmProvider');
  const setProperty = module.findExportByName('BCryptSetProperty');
  const getPropertyPtr = module.findExportByName('BCryptGetProperty');
  const generate = module.findExportByName('BCryptGenerateSymmetricKey');
  const importKey = module.findExportByName('BCryptImportKey');
  const duplicateKey = module.findExportByName('BCryptDuplicateKey');
  const exportKeyPtr = module.findExportByName('BCryptExportKey');
  const destroy = module.findExportByName('BCryptDestroyKey');
  const decrypt = module.findExportByName('BCryptDecrypt');

  const getProperty = getPropertyPtr
      ? new NativeFunction(
          getPropertyPtr,
          'uint32',
          ['pointer', 'pointer', 'pointer', 'uint32', 'pointer', 'uint32'],
        )
      : null;
  const exportKey = exportKeyPtr
      ? new NativeFunction(
          exportKeyPtr,
          'uint32',
          [
            'pointer',
            'pointer',
            'pointer',
            'pointer',
            'uint32',
            'pointer',
            'uint32',
          ],
        )
      : null;

  function readWideProperty(handle, name) {
    if (!getProperty) return null;
    try {
      const propertyName = Memory.allocUtf16String(name);
      const output = Memory.alloc(256);
      const written = Memory.alloc(4);
      written.writeU32(0);
      const status = getProperty(
        handle,
        propertyName,
        output,
        256,
        written,
        0,
      );
      if (status !== 0) return null;
      const bytes = written.readU32();
      if (bytes < 2 || bytes > 256) return null;
      return output.readUtf16String(Math.floor(bytes / 2)).replace(/\0+$/, '');
    } catch (_) {
      return null;
    }
  }

  function exportSecret(handle) {
    if (!exportKey) return null;
    try {
      const blobType = Memory.allocUtf16String('KeyDataBlob');
      const required = Memory.alloc(4);
      required.writeU32(0);
      let status = exportKey(
        handle,
        ptr(0),
        blobType,
        ptr(0),
        0,
        required,
        0,
      );
      if (status !== 0 && status !== 0xc0000023) return null;
      const bytes = required.readU32();
      if (bytes < 28 || bytes > 4096) return null;

      const output = Memory.alloc(bytes);
      required.writeU32(0);
      status = exportKey(
        handle,
        ptr(0),
        blobType,
        output,
        bytes,
        required,
        0,
      );
      if (status !== 0) return null;

      const actual = required.readU32();
      if (actual < 12 || actual > bytes) return null;
      const magic = output.readU32();
      const version = output.add(4).readU32();
      const secretBytes = output.add(8).readU32();
      if (magic !== 0x4d42444b || version !== 1) return null;
      if (![16, 24, 32].includes(secretBytes)) return null;
      if (12 + secretBytes > actual) return null;

      return {
        algorithm: 'AES',
        chainingMode: readWideProperty(handle, 'ChainingMode'),
        secretHex: safe(output.add(12), secretBytes, 256),
        secretBytes,
        source: 'BCryptExportKey:KeyDataBlob',
      };
    } catch (_) {
      return null;
    }
  }

  function keyFor(handle) {
    const id = handle.toString();
    let key = keys.get(id) || null;
    if (!key || !key.secretHex) {
      const exported = exportSecret(handle);
      if (exported && exported.secretHex) {
        keys.set(id, exported);
        key = exported;
        event('KEY_EXPORTED_FROM_LIVE_HANDLE', {
          secretBytes: exported.secretBytes,
          chainingMode: exported.chainingMode,
        });
      }
    } else if (!key.chainingMode) {
      key.chainingMode = readWideProperty(handle, 'ChainingMode');
    }
    return key;
  }

  if (open) {
    listeners.push(
      Interceptor.attach(open, {
        onEnter(args) {
          this.out = args[0];
          try {
            this.name = args[1].readUtf16String();
          } catch (_) {
            this.name = '?';
          }
        },
        onLeave(status) {
          try {
            if (status.toUInt32() === 0) {
              algs.set(this.out.readPointer().toString(), this.name);
            }
          } catch (_) {}
        },
      }),
    );
  }

  if (setProperty) {
    listeners.push(
      Interceptor.attach(setProperty, {
        onEnter(args) {
          try {
            const handle = args[0].toString();
            const name = args[1].readUtf16String();
            const bytes = args[3].toUInt32();
            let text = null;
            try {
              text = args[2].readUtf16String(Math.floor(bytes / 2));
            } catch (_) {}
            props.set(handle + ':' + name, {
              name,
              text,
              hex: safe(args[2], bytes, 512),
            });
            const key = keys.get(handle);
            if (key && name === 'ChainingMode') key.chainingMode = text;
          } catch (_) {}
        },
      }),
    );
  }

  if (generate) {
    listeners.push(
      Interceptor.attach(generate, {
        onEnter(args) {
          this.algorithm = args[0].toString();
          this.out = args[1];
          this.secretBytes = args[5].toUInt32();
          this.secret =
              this.secretBytes > 0 && this.secretBytes <= 256
                  ? safe(args[4], this.secretBytes, 256)
                  : null;
        },
        onLeave(status) {
          try {
            if (status.toUInt32() !== 0 || !this.secret) return;
            const handle = this.out.readPointer().toString();
            const mode = props.get(this.algorithm + ':ChainingMode');
            keys.set(handle, {
              algorithm: algs.get(this.algorithm) || '?',
              chainingMode: mode && mode.text ? mode.text : null,
              secretHex: this.secret,
              secretBytes: this.secretBytes,
              source: 'BCryptGenerateSymmetricKey',
            });
          } catch (_) {}
        },
      }),
    );
  }

  if (importKey) {
    listeners.push(
      Interceptor.attach(importKey, {
        onEnter(args) {
          this.algorithm = args[0].toString();
          this.out = args[3];
          this.secret = null;
          this.secretBytes = 0;
          this.blobType = '';
          try {
            this.blobType = args[2].readUtf16String() || '';
            const bytes = args[7].toUInt32();
            const input = args[6];
            if (
              this.blobType.toLowerCase() === 'keydatablob' &&
              bytes >= 28 &&
              bytes <= 4096
            ) {
              const magic = input.readU32();
              const version = input.add(4).readU32();
              const keyBytes = input.add(8).readU32();
              if (
                magic === 0x4d42444b &&
                version === 1 &&
                [16, 24, 32].includes(keyBytes) &&
                12 + keyBytes <= bytes
              ) {
                this.secret = safe(input.add(12), keyBytes, 256);
                this.secretBytes = keyBytes;
              }
            }
          } catch (_) {}
        },
        onLeave(status) {
          try {
            if (status.toUInt32() !== 0) return;
            const handlePointer = this.out.readPointer();
            const handle = handlePointer.toString();
            let key = null;
            if (this.secret) {
              const mode = props.get(this.algorithm + ':ChainingMode');
              key = {
                algorithm: algs.get(this.algorithm) || '?',
                chainingMode: mode && mode.text ? mode.text : null,
                secretHex: this.secret,
                secretBytes: this.secretBytes,
                source: 'BCryptImportKey:KeyDataBlob',
              };
            } else {
              key = exportSecret(handlePointer);
            }
            if (key && key.secretHex) keys.set(handle, key);
          } catch (_) {}
        },
      }),
    );
  }

  if (duplicateKey) {
    listeners.push(
      Interceptor.attach(duplicateKey, {
        onEnter(args) {
          this.source = args[0].toString();
          this.out = args[1];
        },
        onLeave(status) {
          try {
            if (status.toUInt32() !== 0) return;
            const handlePointer = this.out.readPointer();
            const original = keys.get(this.source);
            const key = original
                ? Object.assign({}, original, {
                    source: (original.source || 'unknown') + '+duplicate',
                  })
                : exportSecret(handlePointer);
            if (key && key.secretHex) {
              keys.set(handlePointer.toString(), key);
            }
          } catch (_) {}
        },
      }),
    );
  }

  if (destroy) {
    listeners.push(
      Interceptor.attach(destroy, {
        onEnter(args) {
          keys.delete(args[0].toString());
        },
      }),
    );
  }

  if (!decrypt) {
    event('NO_BCRYPT_DECRYPT');
    return;
  }

  listeners.push(
    Interceptor.attach(decrypt, {
      onEnter(args) {
        this.hit = null;
        if (!active || captures >= 30) return;
        try {
          const inputBytes = args[2].toUInt32();
          if (inputBytes < 6) return;

          const prefix = hex(args[1].readByteArray(6));
          const expectedBytes = CONFIG.prefixes[prefix];
          if (expectedBytes === undefined || expectedBytes !== inputBytes) {
            return;
          }

          const full = args[1].readByteArray(inputBytes);
          const digest = Checksum.compute('sha256', full);
          const unique = prefix + ':' + digest;
          if (seen.has(unique)) return;

          this.hit = {
            prefix,
            inputSha256: digest,
            inputBytes,
            caller: location(this.returnAddress),
            flags: args[9].toUInt32(),
            key: keyFor(args[0]),
            auth: authenticatedInfo(args[3]),
            ivHex: safe(args[4], args[5].toUInt32(), 256),
          };
          this.output = args[6];
          this.capacity = args[7].toUInt32();
          this.result = args[8];
        } catch (error) {
          event('MATCH_ERROR', {message: String(error).slice(0, 220)});
        }
      },
      onLeave(status) {
        if (!this.hit) return;
        try {
          const code = status.toUInt32();
          if (code !== 0) {
            event('MATCH_FAIL', {status: '0x' + code.toString(16)});
            return;
          }

          const key = this.hit.key || {};
          const auth = this.hit.auth || {};
          const completeCrypto =
              Boolean(key.secretHex) &&
              [16, 32].includes(key.secretBytes) &&
              Boolean(auth.nonceHex) &&
              auth.nonceBytes === 12 &&
              Boolean(auth.tagHex) &&
              auth.tagBytes === 16;
          if (!completeCrypto) {
            event('RESOURCE_MATCH_INCOMPLETE_CRYPTO', {
              caller: this.hit.caller,
              hasKey: Boolean(key.secretHex),
              secretBytes: key.secretBytes || 0,
              hasAuth: Boolean(this.hit.auth),
              nonceBytes: auth.nonceBytes || 0,
              tagBytes: auth.tagBytes || 0,
            });
            // No se marca como visto: una llamada posterior con el mismo
            // ciphertext puede ocurrir cuando el handle ya sea exportable.
            return;
          }

          seen.add(this.hit.prefix + ':' + this.hit.inputSha256);
          let bytes = null;
          let outputBytes = 0;
          if (!this.output.isNull() && !this.result.isNull()) {
            outputBytes = this.result.readU32();
            if (
              outputBytes > 0 &&
              outputBytes <= this.capacity &&
              outputBytes <= 8 * 1024 * 1024
            ) {
              bytes = this.output.readByteArray(outputBytes);
            }
          }
          this.hit.kind = 'resource';
          this.hit.outputBytes = outputBytes;
          this.hit.outputSha256 = bytes
              ? Checksum.compute('sha256', bytes)
              : null;
          captures++;
          send(this.hit, bytes);
        } catch (error) {
          event('OUTPUT_ERROR', {message: String(error).slice(0, 220)});
        }
      },
    }),
  );

  event('HOOK_READY', {
    targets: Object.keys(CONFIG.prefixes).length,
    exportKeyFallback: Boolean(exportKey),
    importKeyHook: Boolean(importKey),
    duplicateKeyHook: Boolean(duplicateKey),
  });
}

if (
  Process.platform !== 'windows' ||
  !['x64', 'ia32'].includes(Process.arch)
) {
  throw new Error('Windows x86/x64 requerido');
}

observer = Process.attachModuleObserver({
  onAdded(module) {
    try {
      attach(module);
    } catch (error) {
      event('HOOK_ERROR', {message: String(error).slice(0, 220)});
    }
  },
});

rpc.exports = {
  stop() {
    active = false;
    for (const listener of listeners) {
      try {
        listener.detach();
      } catch (_) {}
    }
    if (observer) {
      try {
        observer.detach();
      } catch (_) {}
    }
    return {caps: captures};
  },
};

event('READY', {
  scope: 'exact-SPK-resource-ciphertexts-only',
  liveHandleKeyExport: true,
  targetArch: Process.arch,
  pointerSize: Process.pointerSize,
});
