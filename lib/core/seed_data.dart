// SEED S-boxes and round key derived from Parsec (MIT). See THIRD_PARTY_NOTICES.md.
import 'dart:convert';
import 'dart:typed_data';

class SeedData {
  static final _box = ByteData.sublistView(
    base64Decode(
      'qKGJKYSBhQXU0sYW0NPDE1RQRBQcEQ0drKCMLCQhBSVcUU0dQENDAxgQCBgcEg4eUFFBEfzwzDzIwsoKYGNDIyggCChEQEQEICAAIJyRjR3g4MAg4OLCIsjAyAgUEwcXpKGFJYyDjw8AAwMDeHNLO7izizsQEwMT0NLCEuzizi5wcEAwjICMDDwzDz+ooIgoMDICMtzRzR308sY2dHBENOzgzCyUkYUVCAMLC1RTRxdcUEwcWFNLG7yxjT0AAQEBJCAEJBwQDBxwc0MzmJCIGBAQABDMwMwM8PLCMtjRyRksIAws5OPHJ3ByQjKAg4MDmJOLG9DRwRGEgoYGyMHJCWBgQCBQUEAQoKODI+jjyysMAQ0NtLKGNpySjh5MQ08PtLOHN1hSShrEwsYGeHBIOKSihiYQEgISrKOPL9TRxRVgYUEhwMPDA7SwhDRAQUEBUFJCEnxxTT2MgY0NCAAICBwTDx+YkYkZAAAAABgRCRkEAAQEUFNDE/Tzxzfg4cEh/PHNPXRyRjYsIw8vJCMHJ7CwgDCIg4sLDAIODqijiyugooIibGJOLpCTgxNMQU0NaGFJKXxwTDwIAQkJCAIKCryzjz/s488v8PPDM8TBxQWEg4cHFBAEFPzyzj5kYEQk3NLOHiwiDi5IQ0sLGBIKGgQCBgYgIQEhaGNLK2RiRiYAAgIC9PHFNZCSghKIgooKDAAMDLCzgzN8ck4+0NDAEHhySjpEQ0cHlJKGFuThxSUkIgYmgICAAKyhjS3c088foKGBITAwADA0Mwc3rKKOLjQyBjYUEQUVICICIjgwCDj08MQ0pKOHJ0RBRQVMQEwMgIGBAejhySmEgIQElJOHFzQxBTXIw8sLzMLODjwwDDxwcUExEBEBEcTDxweIgYkJdHFFNfjzyzvY0soa+PDIOJSQhBRYUUkZgIKCAsTAxAT8888/SEFJCTgxCTlkY0cnwMDAAMzDzw/U08cXuLCIOAwDDw+Mgo4OQEJCAiAjAyOQkYERbGBMLNjTyxukoIQkNDAENPDxwTFIQEgIwMLCAmxjTy88MQ09LCENLUBAQAC8so4+PDIOPrywjDzAwcEBqKKKKriyijpMQk4OVFFFFTgzCzvc0MwcaGBIKHxzTz+ckIwc2NDIGEhCSgpUUkYWdHNHN6CggCDs4c0tREJGBrSxhTUoIwsrZGFFJfjyyjrg48MjuLGJObCxgTGck48fXFJOHvjxyTnk4sYmsLKCMjAxATHo4soqbGFNLVxTTx/k4MQk8PDAMMzBzQ2IgIgIFBIGFjgyCjpYUEgY1NDEFGBiQiIoIQkpBAMHBzAzAzPo4MgoGBMLGwQBBQV4cUk5kJCAEGhiSiooIgoqmJKKGjAIODjgyCjoIQ0tLKKGJqTDzw/M0s4e3LODM7CwiDi4o48vrGBAIGBRRRVUw8cHxEBEBERjTy9sY0sraFNLG1jDwwPAYkIiYDMDMzCxhTW0IQkpKKCAIKDiwiLgo4cnpNPDE9CRgRGQEQEREAIGBgQQDBwcsIw8vDIGNjRDSwtI488v7ICICIhgTCxsoIgoqBMHFxTAxATEEgYWFPDENPTCwgLAQUUFROHBIeDSxhbUMw8/PDENPTyCjg6MkIgYmCAIKChCTg5M8sY29DIOPjyhhSWk8ck5+AENDQzTzx/c0MgY2CMLKyhiRiZkcko6eCMHJyQjDy8s8cEx8HJCMnBCQgJA0MQU1EFBAUDAwADAc0MzcGNHJ2SgjCysg4sLiPPHN/ShjS2sgIAAgBMPHxzCygrIIAwsLKKKKqgwBDQ00sIS0AMLCwjizi7s4ckp6FFNHVyQhBSUEAgYGPDIOPhTRxdUoo4urAAICAjBxQXEEwMTEMHNDcyChgaEsYk5uPPPP/xxTT18wcEBwDEBMTDxxTX0gooKiGJKKmixgTGw0cER0CAAICDTxxfUAgICACICIiAABAQEYEgoaHFBMXADBwcE08sb2JGNHZyRiRmYYUEhYLKOPrzixibkUUkZWNHNHdxRQRFQkIAQkNDMHNySihqYo4MjoKOLK6jQwBDQgYEBgAMPDwxDRwdEEgoaGOPDI+DgzCzsgY0NjLOPP7yShhaUc0s7eFBMHFyigiKgoYEhoGNDI2AjAyMgQU0NTMDICMiSjh6ckIwcnDIKOjgADAwMIg4uLLKKOrhiTi5sk48fnFJKGljywjLwkoISkPPDM/BBSQlIcEg4eMDMDMwRBRUU88s7+HBAMHBxRTV0c08/fDEFNTQQABAQAwMDAGBEJGRhTS1swsYGxHBENHTRxRXUsIQ0tOLKKugBCQkIckY2dBEJGRjyzj78QEAAQBICEhDgwCDgsY09vAEFBQTyyjr4AQEBAPDAMPAiCiooUk4eXKGJKahSRhZUQ0MDQIGFBYQQBBQUgYkJiJOLG5iwgDCw4cUl5EBICEhxSTl4k4cXlPDMPPwSDh4cgoICgCEBISCAjAyMEwsbGFNPH1xzRzd0UEQUVLKCMrARDR0cIQUlJENPD0wAAAAAQkYGROHNLexQSBhYUkISUOPLK+hyTj580soa2MHJCcjxzT38MAAwMJGFFZRhRSVkMAw8PLKGNrTgxCTks4s7uHBMPHwCDg4MUEAQUDEJOTgiBiYkMgIyMICEBIRhSSlok4MTkDMHNzTjxyfkIAQkJKCEJKTDywvIU0MTUAIKCgiDhweE0ckZ2EBMDEyDgwOAg48PjMLODswzCzs4QkoKSLOHN7SJKaihhQWEgcYW1NLDE9DTRBRUUA0dHBGMLKygBSUkIU0dXFFDA0BDCBgYEA4eHBJBEVBRzDz88MoKyMJDI2BjCCgoIEQEREAAICAgjR2ckcAg4ODCIuDiyAjIwAcXFBOFJaShjw+MgwMDAANLO3hzizu4swMTEBPCEtDSzi7s4kAwcHCMDIyADz88M4goqKACMjAyzR3c0cY29PJENHRwzCzs4IUVlJELCwgDRxdUU0wcXFBLG1hTjT28sQEBAAEEJCQgDBwcEEMzcHOIGJiQABAQEMwMzMDCMvDyyRnY0QwsLCDHJ+TjQjJwcoMDgIOLG5iTwRHQ0YYGhILJCcjBQCBgYEAQUFCDI6Cjyyvo4w0NDAGGNrSyjh6ckk8PTEOHN7SzShpYUsYGxMJIOHhwhiakogISEBKPL6yjxRXU0UEhYGHDA8DDhDS0sEEBQEFCElBSTT18cY0NjIEICAgADx8cE4kZmJEAAAAACRkYEQQEBABDE1BTxzf088Eh4OHNPfzxRjZ0cg8vLCMHJyQjgDCwsIsLiIMODgwCiyuoo4IioKJOLmxigxOQk00NTEFJKWhhTDx8cAkJCAEKCggCjz+8s88v7OPDM/DzxQXEwYcHhIMEFBQQzj788kQkZGDOHtzSDi4sIksLSEMKGhgSBgYEAgEhICFLK2hjRiZkYgICAALFNfTxghKQkooKiIIMDAwAgzOws04+fHLAENDQSjp4ckcHREOGFpSSxSXk4QYmJCKAAICAjS2soc8f3NOBIaChADAwMAc3NDOOLqyiBjY0MgUVFBECIiAiCDg4MMQ09PCHJ6SjRQVEQUwMTECBAYCBySno4YQEhICHF5STBTU0McsLyMPODszCDDw8MEExcHEBERARxwfEw4kJiIFFNXRxyzv488oa2NLIOPjwhBSUkEkZWFGCAoCCxATEwM8//PNJCUhBCTk4MUcnZGPAAMDAzw/Mw8cX1NOIOLiwDw8MA44OjIJCAkBCAyMgI4ERkJFMLGxgyxvY04QkpKAENDQwwTHw8UgISEDCAsDCTy9sYw09PDENLSwhQABAQI4+vLIOPjwyjDy8sMEBwMGKKqiiijq4sk4OTEJFFVRRCzs4M8wc3NBIKGhgTz98c4wcnJDIGNjQSgpIQkYWVFJHN3RzgCCgoM0t7OFGBkRChTW0sQsrKCNFJWRhyjr48sMj4OOJObixgTGwsY8fnJNOHlxSyTn48cYm5OKCMrCyATEwMcoq6OJNLWxhTx9cU8Qk5ODAMPDwzQ3MwYgIiIAGFhQSCjo4MkgYWFDEFNTQQiJgYgkpKCEHBwQDAzMwM8go6OALGxgTBQUEAUk5eHGAEJCQSipoYgoqKCKKGpiSODgwCCjo4MgtLCENJqSihg/Mw88e3NLOM7Czgzi4sIgvrKOPIGBgQBVUUUUHxMPHBERARC9sY08raGNLG1hTSwPAw8MiYGJCMzAzAzW0sYUpKCEJIKCggCLg4sInpKOHE9DTwxGQkYEREBEBBgQCBhwcEAw8vLCMNjQyBgtIQ0sv7OPPCIiAiCxsYEwoqKCIFxQTBwTEwMQWFBIGNPTwxALAwsIFREFFIeDhwRbU0sY/PDMPPTwxDQ6Mgo4YmJCIKCggCA5MQk429PLGPjwyDiWkoYU5+PHJDQwBDR/c088Y2NDIKygjCyZkYkY6eHJKJyQjBy8sIw8x8PHBMnByQgJAQkIU1NDEAUBBQQDAwMAzcHNDJ2RjRyysoIwLiIOLN/Tzxy2soY0AgICAHxwTDwrIwsosLCAMKqiiijQ0MAQS0NLCCwgDCy7s4s4p6OHJHVxRTRSUkIQYGBAIOPjwyBdUU0curKKOCAgACAXEwcUTEBMDDczBzQaEgoY5uLGJP/zzzz18cU0BwMHBMTAxATX08cUKiIKKKmhiSjGwsYER0NHBICAgABfU08cCAAICIiAiAgQEAAQoaGBIMXBxQQcEAwcb2NPLHZyRjRmYkYkhYGFBPryyjibk4sYZWFFJHdzRzRFQUUEQkJCAHNzQzBqYkoojoKODK6ijixDQ0MABgIGBDwwDDwdEQ0caGBIKI+Djwyzs4MwNjIGNP7yzjxaUkoY7eHNLHFxQTCKgooIhoKGBI2BjQyMgIwMNTEFNCMjAyB6cko4cnJCMOjgyCgwMAAwuLCIOOriyii5sYk4fnJOPGlhSSjLw8sISkJKCM/DzwwlIQUk4eHBIDMzAzBUUEQU7+PPLMHBwQDV0cUU/fHNPNTQxBRAQEAADAAMDJGRgRC1sYU0GxMLGNHRwRBXU0cU0tLCEKujiygkIAQk2dHJGGRgRCT788s4AQEBAEhASAiDg4MA9vLGNBQQBBTr48soBAAEBMPDwwCooIgoeXFJOKaihiRZUUkYDQENDBYSBhRQUEAQJiIGJG5iTizCwsIAl5OHFCEhASDl4cUkXlJOHPPzwzB4cEg4CgIKCISAhAQyMgIwbGBMLH1xTTzd0c0cUVFBEMrCygh0cEQ0lJCEFD0xDTwAAAAAGREJGLezhzRhYUEgSUFJCK+jjyz58ck4a2NLKCcjByT388c0wMDAAFZSRhSVkYUU8PDAMNrSyhiTk4MQ7uLOLPHxwTA4MAg4QUFBAOTgxCSYkIgYyMDICBISAhCloYUkTkJODNzQzByfk48ckJCAEJKSghAvIw8sTUFNDCggCCgeEg4cZ2NHJDExATAOAg4MPjIOPDszCzjs4MwsKSEJKN7Szhw==',
    ),
  );
  static const _keys = <int>[
    0x79f5dbde,
    0x345ac74a,
    0xf482438,
    0x131f493,
    0x81a8500c,
    0x659bdcf,
    0x26ff71c1,
    0x86e9a5cb,
    0xca6fb745,
    0x50e2c1ae,
    0x381ddae1,
    0xc3402821,
    0x3feccb4a,
    0x3e0be066,
    0x372582ff,
    0x826317e3,
    0xa47b5369,
    0xc9093c0e,
    0xe16c9cb1,
    0x2e27228e,
    0x84e2d1cd,
    0xc840f818,
    0x44aea6f8,
    0xd298548d,
    0x2040ca27,
    0x4b4e2b78,
    0x64f0a045,
    0xc171a8da,
    0x384855ed,
    0xc033578b,
    0x2a8703c7,
    0xf15da3a7,
  ];
  static int _g(int x) =>
      _box.getUint32((x & 255) * 4, Endian.little) ^
      _box.getUint32((256 + ((x >> 8) & 255)) * 4, Endian.little) ^
      _box.getUint32((512 + ((x >> 16) & 255)) * 4, Endian.little) ^
      _box.getUint32((768 + ((x >> 24) & 255)) * 4, Endian.little);
  static Uint8List decode(Uint8List bytes, {bool verifyChecksum = false}) {
    if (bytes.length < 40 ||
        ascii.decode(bytes.sublist(0, 40), allowInvalid: true) !=
            '0001CBCEBC5B2784D3FC9A2A9DB84D1C3FEB6E99') {
      return bytes;
    }
    if (bytes.length < 64 || (bytes.length - 64) % 16 != 0) {
      throw const FormatException('Tabla SData truncada.');
    }
    final input = ByteData.sublistView(bytes),
        out = Uint8List(bytes.length - 64),
        d = ByteData.sublistView(out);
    final marker = input.getUint32(40, Endian.little),
        size = input.getUint32(marker == 0 ? 48 : 44, Endian.little),
        checksum = input.getUint32(marker == 0 ? 44 : 40, Endian.little);
    if (size > out.length) {
      throw const FormatException('Tamaño SData fuera del archivo.');
    }
    for (var offset = 64; offset < bytes.length; offset += 16) {
      var l0 = input.getUint32(offset),
          l1 = input.getUint32(offset + 4),
          r0 = input.getUint32(offset + 8),
          r1 = input.getUint32(offset + 12);
      for (var round = 30; round >= 0; round -= 2) {
        var a = r0 ^ _keys[round], b = r1 ^ _keys[round + 1];
        b = _g(b ^ a);
        a = _g((a + b) & 0xffffffff);
        b = _g((a + b) & 0xffffffff);
        a = (a + b) & 0xffffffff;
        final t0 = l0 ^ a, t1 = l1 ^ b;
        l0 = r0;
        l1 = r1;
        r0 = t0;
        r1 = t1;
      }
      d.setUint32(offset - 64, r0);
      d.setUint32(offset - 60, r1);
      d.setUint32(offset - 56, l0);
      d.setUint32(offset - 52, l1);
    }
    final result = Uint8List.sublistView(out, 0, size);
    if (verifyChecksum) {
      var crc = 0xffffffff;
      for (final b in result) {
        crc ^= b;
        for (var k = 0; k < 8; k++) {
          crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
        }
      }
      if (((~crc) & 0xffffffff) != checksum) {
        throw const FormatException('Checksum SData no coincide.');
      }
    }
    return result;
  }
}
