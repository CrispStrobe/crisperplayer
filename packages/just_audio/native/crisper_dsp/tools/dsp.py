# SPDX-License-Identifier: MIT
"""Small ctypes binding shared by the deterministic tests and WAV renderer."""
from array import array
import ctypes as C
from pathlib import Path

ENGINES = {'sonic': 0, 'bungee': 1, 'signalsmith': 2, 'wsola': 3}
DEFAULT_LIBRARY = Path(__file__).resolve().parents[5] / 'build/native-dsp/libcrisper_dsp.so'


class Library:
    def __init__(self, path=DEFAULT_LIBRARY):
        self.path = Path(path)
        self.lib = C.CDLL(str(self.path))
        self.lib.cp_dsp_create.argtypes = [C.c_int, C.c_int, C.c_int, C.c_double]
        self.lib.cp_dsp_create.restype = C.c_void_p
        self.lib.cp_dsp_destroy.argtypes = [C.c_void_p]
        self.lib.cp_dsp_destroy.restype = None
        self.lib.cp_dsp_last_error.restype = C.c_char_p
        for name in ('available', 'finish', 'ended', 'latency_frames'):
            fun = getattr(self.lib, 'cp_dsp_' + name)
            fun.argtypes, fun.restype = [C.c_void_p], C.c_int
        for name in ('source_frames', 'output_frames', 'input_frames'):
            fun = getattr(self.lib, 'cp_dsp_' + name)
            fun.argtypes, fun.restype = [C.c_void_p], C.c_int64
        self.lib.cp_dsp_reset.argtypes = [C.c_void_p, C.c_double]
        self.lib.cp_dsp_reset.restype = C.c_int
        for name, typ in (('f32', C.c_float), ('s16', C.c_int16)):
            for verb in ('read', 'write'):
                fun = getattr(self.lib, 'cp_dsp_' + verb + '_' + name)
                fun.argtypes = [C.c_void_p, C.POINTER(typ), C.c_int]
                fun.restype = C.c_int

    def check(self, result):
        if result is None or result == -1:
            raise RuntimeError(self.lib.cp_dsp_last_error().decode())
        return result

    def create(self, engine, sample_rate, channels, rate):
        return Processor(self, engine, sample_rate, channels, rate)


class Processor:
    def __init__(self, library, engine, sample_rate, channels, rate):
        self.library, self.channels, self.rate = library, channels, rate
        self.handle = library.check(library.lib.cp_dsp_create(ENGINES.get(engine, engine), sample_rate, channels, rate))

    def close(self):
        if self.handle:
            self.library.lib.cp_dsp_destroy(self.handle)
            self.handle = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def stat(self, name):
        return self.library.check(getattr(self.library.lib, 'cp_dsp_' + name)(self.handle))

    def write(self, samples, start=0, frames=None):
        typ = C.c_int16 if samples.typecode == 'h' else C.c_float
        if samples.typecode not in ('f', 'h'):
            raise TypeError('Expected an array of PCM floats or signed int16')
        if frames is None:
            frames = len(samples) // self.channels - start
        raw = (typ * len(samples)).from_buffer(samples)
        pointer = C.cast(C.byref(raw, start * self.channels * C.sizeof(typ)), C.POINTER(typ))
        suffix = 's16' if samples.typecode == 'h' else 'f32'
        return self.library.check(getattr(self.library.lib, 'cp_dsp_write_' + suffix)(self.handle, pointer, frames))

    def read(self, frames=4096, pcm16=False):
        typ, code = (C.c_int16, 'h') if pcm16 else (C.c_float, 'f')
        raw = (typ * (frames * self.channels))()
        suffix = 's16' if pcm16 else 'f32'
        n = self.library.check(getattr(self.library.lib, 'cp_dsp_read_' + suffix)(self.handle, raw, frames))
        result = array(code)
        result.frombytes(C.string_at(raw, n * self.channels * C.sizeof(typ)))
        return result

    def finish(self):
        self.library.check(self.library.lib.cp_dsp_finish(self.handle))

    def reset(self, rate):
        self.library.check(self.library.lib.cp_dsp_reset(self.handle, rate))
        self.rate = rate


def render(processor, samples, chunks=(1, 7, 31, 511, 4096, 2, 257), read_sizes=(17, 1024, 4096)):
    """Drive partial writes and arbitrary reads without losing accepted frames."""
    frames, offset, index = len(samples) // processor.channels, 0, 0
    result = array(samples.typecode)
    while offset < frames:
        requested = min(chunks[index % len(chunks)], frames - offset)
        consumed = processor.write(samples, offset, requested)
        offset += consumed
        result.extend(processor.read(read_sizes[index % len(read_sizes)], samples.typecode == 'h'))
        if consumed == 0 and processor.stat('available') == 0:
            raise RuntimeError('Native input/output deadlock')
        index += 1
        if index > frames * 2 + 1000:
            raise RuntimeError('Input consumption failed to converge')
    processor.finish()
    processor.finish()
    for _ in range(frames * 2 + 1000):
        if processor.stat('ended'):
            break
        result.extend(processor.read(read_sizes[index % len(read_sizes)], samples.typecode == 'h'))
        index += 1
    else:
        raise RuntimeError('EOS drain failed to converge')
    return result
