'use strict';

const CONFIG = __CONFIG__;
const hooks = new Set();
const listeners = [];
const algs = new Map();
const props = new Map();
const keys = new Map();
const seen = new Set();
const candidateSeen = new Set();
const candidateHooks = new Set();
let observer = null;
let active = true;
let events = 0;
let captures = 0;

function event(code, details = {}) {
  if (events++ < 250) send({kind: 'event', code, details});
}

function emitCandidate(secretHex, secretBytes, source, details = {}) {
  if (!active || !secretHex || ![16, 32].includes(secretBytes)) return;
  if (candidateSeen.size >= 4096) return;
  const normalized = secretHex.toLowerCase();
  if (candidateSeen.has(normalized)) return;
  candidateSeen.add(normalized);
  send({
    kind: 'candidate-key',
    secretHex: normalized,
    secretBytes,
    source,
    details,
  });
  event('KEY_CANDIDATE_OBSERVED', {source, secretBytes});
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

function attachCandidateModule(module) {
  const lower = module.name.toLowerCase();
  if (
    lower !== 'bcrypt.dll' &&
    !lower.includes('crypto') &&
    !lower.includes('libeay') &&
    !lower.includes('mbedtls') &&
    !lower.includes('mbedcrypto') &&
    !lower.includes('wolfssl') &&
    !lower.includes('boringssl')
  ) {
    return;
  }

  function hook(symbol, callbacks) {
    const address = module.findExportByName(symbol);
    if (!address) return false;
    const key = address.toString();
    if (candidateHooks.has(key)) return true;
    candidateHooks.add(key);
    listeners.push(Interceptor.attach(address, callbacks));
    event('CANDIDATE_HOOK_READY', {module: module.name, symbol});
    return true;
  }

  function derivedBuffer(symbol, outputIndex, bytesIndex) {
    hook(symbol, {
      onEnter(args) {
        this.output = args[outputIndex];
        try {
          this.bytes = args[bytesIndex].toUInt32();
        } catch (_) {
          this.bytes = 0;
        }
      },
      onLeave(status) {
        try {
          if (status.toUInt32() !== 0 || ![16, 32].includes(this.bytes)) {
            return;
          }
          const secretHex = safe(this.output, this.bytes, 64);
          emitCandidate(secretHex, this.bytes, symbol, {
            module: module.name,
            source: 'derived-buffer',
          });
        } catch (_) {}
      },
    });
  }

  derivedBuffer('BCryptKeyDerivation', 2, 3);
  derivedBuffer('BCryptDeriveKeyCapi', 2, 3);
  derivedBuffer('BCryptFinishHash', 1, 2);

  const pbkdf2 = module.findExportByName('BCryptDeriveKeyPBKDF2');
  if (pbkdf2 && !candidateHooks.has(pbkdf2.toString())) {
    candidateHooks.add(pbkdf2.toString());
    listeners.push(
      Interceptor.attach(pbkdf2, {
        onEnter(args) {
          // cIterations is ULONGLONG: on x86 it consumes two stack slots.
          const outputIndex = Process.pointerSize === 8 ? 6 : 7;
          const bytesIndex = Process.pointerSize === 8 ? 7 : 8;
          this.output = args[outputIndex];
          try {
            this.bytes = args[bytesIndex].toUInt32();
          } catch (_) {
            this.bytes = 0;
          }
        },
        onLeave(status) {
          try {
            if (status.toUInt32() !== 0 || ![16, 32].includes(this.bytes)) {
              return;
            }
            emitCandidate(
              safe(this.output, this.bytes, 64),
              this.bytes,
              'BCryptDeriveKeyPBKDF2',
              {module: module.name, source: 'derived-buffer'},
            );
          } catch (_) {}
        },
      }),
    );
    event('CANDIDATE_HOOK_READY', {
      module: module.name,
      symbol: 'BCryptDeriveKeyPBKDF2',
    });
  }

  for (const symbol of ['AES_set_decrypt_key', 'AES_set_encrypt_key']) {
    hook(symbol, {
      onEnter(args) {
        try {
          const bits = args[1].toInt32();
          if (![128, 256].includes(bits)) return;
          const bytes = bits / 8;
          emitCandidate(safe(args[0], bytes, 64), bytes, symbol, {
            module: module.name,
            source: 'openssl-aes-key',
          });
        } catch (_) {}
      },
    });
  }

  for (const symbol of [
    'EVP_DecryptInit_ex',
    'EVP_CipherInit_ex',
    'EVP_EncryptInit_ex',
  ]) {
    hook(symbol, {
      onEnter(args) {
        const keyPointer = args[3];
        if (!keyPointer || keyPointer.isNull()) return;
        for (const bytes of [16, 32]) {
          emitCandidate(safe(keyPointer, bytes, 64), bytes, symbol, {
            module: module.name,
            source: 'openssl-evp-key',
            candidateBytes: bytes,
          });
        }
      },
    });
  }

  for (const symbol of [
    'EVP_DecryptInit_ex2',
    'EVP_CipherInit_ex2',
    'EVP_EncryptInit_ex2',
  ]) {
    hook(symbol, {
      onEnter(args) {
        const keyPointer = args[2];
        if (!keyPointer || keyPointer.isNull()) return;
        for (const bytes of [16, 32]) {
          emitCandidate(safe(keyPointer, bytes, 64), bytes, symbol, {
            module: module.name,
            source: 'openssl-evp-key',
            candidateBytes: bytes,
          });
        }
      },
    });
  }

  // BoringSSL exposes the AEAD key directly during context initialization.
  // It is still only a candidate: Python must reproduce AES-GCM on the exact
  // DATA.SPK ciphertext/tag samples before Studio accepts it.
  hook('EVP_AEAD_CTX_init', {
    onEnter(args) {
      try {
        const keyPointer = args[2];
        const bytes = args[3].toUInt32();
        if (!keyPointer || keyPointer.isNull() || ![16, 32].includes(bytes)) {
          return;
        }
        emitCandidate(safe(keyPointer, bytes, 64), bytes, 'EVP_AEAD_CTX_init', {
          module: module.name,
          source: 'boringssl-aead-key',
        });
      } catch (_) {}
    },
  });

  // mbedTLS is common in game launchers/clients that do not route symmetric
  // crypto through Windows CNG. These hooks observe only the documented key
  // argument; the offline SPK oracle remains authoritative.
  hook('mbedtls_gcm_setkey', {
    onEnter(args) {
      try {
        const keyPointer = args[2];
        const bits = args[3].toUInt32();
        if (!keyPointer || keyPointer.isNull() || ![128, 256].includes(bits)) {
          return;
        }
        const bytes = bits / 8;
        emitCandidate(safe(keyPointer, bytes, 64), bytes, 'mbedtls_gcm_setkey', {
          module: module.name,
          source: 'mbedtls-gcm-key',
        });
      } catch (_) {}
    },
  });
  for (const symbol of ['mbedtls_aes_setkey_enc', 'mbedtls_aes_setkey_dec']) {
    hook(symbol, {
      onEnter(args) {
        try {
          const keyPointer = args[1];
          const bits = args[2].toUInt32();
          if (!keyPointer || keyPointer.isNull() || ![128, 256].includes(bits)) {
            return;
          }
          const bytes = bits / 8;
          emitCandidate(safe(keyPointer, bytes, 64), bytes, symbol, {
            module: module.name,
            source: 'mbedtls-aes-key',
          });
        } catch (_) {}
      },
    });
  }

  // wolfSSL exposes byte lengths instead of bit lengths.
  for (const symbol of ['wc_AesGcmSetKey', 'wc_AesSetKey']) {
    hook(symbol, {
      onEnter(args) {
        try {
          const keyPointer = args[1];
          const bytes = args[2].toUInt32();
          if (!keyPointer || keyPointer.isNull() || ![16, 32].includes(bytes)) {
            return;
          }
          emitCandidate(safe(keyPointer, bytes, 64), bytes, symbol, {
            module: module.name,
            source: 'wolfssl-aes-key',
          });
        } catch (_) {}
      },
    });
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
        emitCandidate(
          exported.secretHex,
          exported.secretBytes,
          exported.source,
          {module: 'bcrypt.dll', source: 'live-handle-export'},
        );
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
            const key = {
              algorithm: algs.get(this.algorithm) || '?',
              chainingMode: mode && mode.text ? mode.text : null,
              secretHex: this.secret,
              secretBytes: this.secretBytes,
              source: 'BCryptGenerateSymmetricKey',
            };
            keys.set(handle, key);
            emitCandidate(
              key.secretHex,
              key.secretBytes,
              key.source,
              {module: module.name, source: 'key-construction'},
            );
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
            if (key && key.secretHex) {
              keys.set(handle, key);
              emitCandidate(
                key.secretHex,
                key.secretBytes,
                key.source || 'BCryptImportKey',
                {module: module.name, source: 'key-import'},
              );
            }
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
              emitCandidate(
                key.secretHex,
                key.secretBytes,
                key.source || 'BCryptDuplicateKey',
                {module: module.name, source: 'key-duplicate'},
              );
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
      attachCandidateModule(module);
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
  candidateKeyOracle: true,
  candidateHookCount: candidateHooks.size,
  targetArch: Process.arch,
  pointerSize: Process.pointerSize,
});
