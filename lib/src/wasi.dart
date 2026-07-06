/// Minimal WASI Preview 1 shim (SPEC §10.2).
///
/// Lets I/O-using *library* modules — e.g. a `wasmtk modc` library that calls
/// `console.log` (which lowers to `fd_write`) — instantiate on the web platform,
/// which has no native WASI. It covers the small subset such libraries commonly
/// import; anything outside the subset surfaces as a normal missing-import error
/// at instantiation, documenting the gap rather than hiding it. A pure-compute
/// library imports none of this and is unaffected.
///
/// Web platform only — mirrors the reference loader's `wasi.js`.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'wasm_interop.dart';

@JS('console.log')
external void _consoleLog(JSAny? msg);

@JS('console.error')
external void _consoleError(JSAny? msg);

/// A mutable reference to the active WASM linear memory for the WASI shim.
///
/// Set [current] to `instance.exports.memory` after instantiation; WASI calls
/// only happen at run time, by which point it is populated.
class WasiMemRef {
  /// The active memory, or `null` before instantiation.
  WasmMemory? current;
}

const int _errnoSuccess = 0;

/// Writes [value] as a little-endian i64 at [offset]. `ByteData.setInt64` is
/// unsupported on the web, so we split into two 32-bit words.
void _setI64LE(ByteData v, int offset, BigInt value) {
  final x = value.toUnsigned(64);
  final mask = BigInt.from(0xffffffff);
  v.setUint32(offset, (x & mask).toInt(), Endian.little);
  v.setUint32(offset + 4, ((x >> 32) & mask).toInt(), Endian.little);
}

/// Builds a minimal `wasi_snapshot_preview1` import object. The shim reads and
/// writes the module's linear memory through [memRef], which the loader sets to
/// `instance.exports.memory` after instantiation. `fd_write` routes stdout
/// (fd 1) to `console.log` and stderr (fd 2) to `console.error`.
JSObject buildWasiShim(WasiMemRef memRef) {
  final obj = JSObject();
  final dec = const Utf8Decoder();

  ByteData view() => memRef.current!.buffer.toDart.asByteData();
  Uint8List mem() => memoryBytes(memRef.current!);

  // fd_write(fd, iovs, iovs_len, nwritten) -> errno.
  JSAny? fdWrite(
      JSAny? fd, JSAny? iovsPtr, JSAny? iovsLen, JSAny? nwrittenPtr) {
    final v = view();
    final bytes = mem();
    final fdN = (fd as JSNumber).toDartInt;
    final iovs = (iovsPtr as JSNumber).toDartInt;
    final iovsN = (iovsLen as JSNumber).toDartInt;
    final nWritten = (nwrittenPtr as JSNumber).toDartInt;
    var written = 0;
    final sb = StringBuffer();
    for (var i = 0; i < iovsN; i++) {
      final base = iovs + i * 8;
      final ptr = v.getInt32(base, Endian.little);
      final len = v.getInt32(base + 4, Endian.little);
      sb.write(dec.convert(bytes.sublist(ptr, ptr + len)));
      written += len;
    }
    // console.log/error append their own newline; drop one trailing newline.
    var out = sb.toString();
    if (out.endsWith('\n')) out = out.substring(0, out.length - 1);
    if (fdN == 2) {
      _consoleError(out.toJS);
    } else {
      _consoleLog(out.toJS);
    }
    v.setInt32(nWritten, written, Endian.little);
    return _errnoSuccess.toJS;
  }

  // proc_exit(code) -> never. A reactor library should not normally call this.
  JSAny? procExit(JSAny? code) {
    throw StateError('wasm proc_exit(${(code as JSNumber).toDartInt})');
  }

  // random_get(buf, len) -> errno. Fills [buf, buf+len) with random bytes.
  JSAny? randomGet(JSAny? buf, JSAny? len) {
    final bytes = mem();
    final start = (buf as JSNumber).toDartInt;
    final n = (len as JSNumber).toDartInt;
    final rng = Random();
    for (var i = 0; i < n; i++) {
      bytes[start + i] = rng.nextInt(256);
    }
    return _errnoSuccess.toJS;
  }

  // clock_time_get(id, precision, time_ptr) -> errno. Writes i64 ns since epoch.
  JSAny? clockTimeGet(JSAny? id, JSAny? precision, JSAny? timePtr) {
    final ns = BigInt.from(DateTime.now().millisecondsSinceEpoch) *
        BigInt.from(1000000);
    _setI64LE(view(), (timePtr as JSNumber).toDartInt, ns);
    return _errnoSuccess.toJS;
  }

  JSAny? environSizesGet(JSAny? countPtr, JSAny? sizePtr) {
    final v = view();
    v.setInt32((countPtr as JSNumber).toDartInt, 0, Endian.little);
    v.setInt32((sizePtr as JSNumber).toDartInt, 0, Endian.little);
    return _errnoSuccess.toJS;
  }

  JSAny? environGet(JSAny? environPtr, JSAny? environBufPtr) =>
      _errnoSuccess.toJS;

  JSAny? argsSizesGet(JSAny? countPtr, JSAny? sizePtr) {
    final v = view();
    v.setInt32((countPtr as JSNumber).toDartInt, 0, Endian.little);
    v.setInt32((sizePtr as JSNumber).toDartInt, 0, Endian.little);
    return _errnoSuccess.toJS;
  }

  JSAny? argsGet(JSAny? argvPtr, JSAny? argvBufPtr) => _errnoSuccess.toJS;

  JSAny? fdClose(JSAny? fd) => _errnoSuccess.toJS;

  JSAny? fdFdstatGet(JSAny? fd, JSAny? retPtr) => _errnoSuccess.toJS;

  // fd_seek(fd, offset, whence, newoffset_ptr) -> errno.
  JSAny? fdSeek(JSAny? fd, JSAny? offset, JSAny? whence, JSAny? newOffsetPtr) {
    _setI64LE(view(), (newOffsetPtr as JSNumber).toDartInt, BigInt.zero);
    return _errnoSuccess.toJS;
  }

  jsSet(obj, 'fd_write'.toJS, fdWrite.toJS);
  jsSet(obj, 'proc_exit'.toJS, procExit.toJS);
  jsSet(obj, 'random_get'.toJS, randomGet.toJS);
  jsSet(obj, 'clock_time_get'.toJS, clockTimeGet.toJS);
  jsSet(obj, 'environ_sizes_get'.toJS, environSizesGet.toJS);
  jsSet(obj, 'environ_get'.toJS, environGet.toJS);
  jsSet(obj, 'args_sizes_get'.toJS, argsSizesGet.toJS);
  jsSet(obj, 'args_get'.toJS, argsGet.toJS);
  jsSet(obj, 'fd_close'.toJS, fdClose.toJS);
  jsSet(obj, 'fd_fdstat_get'.toJS, fdFdstatGet.toJS);
  jsSet(obj, 'fd_seek'.toJS, fdSeek.toJS);

  return obj;
}
