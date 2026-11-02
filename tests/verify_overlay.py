"""Verify ICO masks and Windows rendering without touching the desktop/settings.

Usage: python tests/verify_overlay.py <generated-icon.ico>
Only uses the Python standard library and off-screen Windows GDI objects.
"""

import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import struct
import sys


SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)


def verify_format(path):
    data = path.read_bytes()
    assert struct.unpack_from('<HHH', data) == (0, 1, len(SIZES))
    end = 6 + 16 * len(SIZES)
    for i, size in enumerate(SIZES):
        width, height, colors, reserved, planes, bpp, length, offset = struct.unpack_from(
            '<BBBBHHII', data, 6 + i * 16)
        assert (width or 256, height or 256, colors, reserved, planes, bpp) == (
            size, size, 2, 0, 1, 1)
        stride = ((size + 31) // 32) * 4
        bitmap_size = stride * size
        assert offset == end and length == 48 + 2 * bitmap_size
        assert struct.unpack_from('<IiiHHIIiiII', data, offset) == (
            40, size, size * 2, 1, 1, 0, 2 * bitmap_size, 0, 0, 2, 0)
        assert data[offset + 40:offset + 48] == bytes.fromhex('00000000ffffff00')
        assert data[offset + 48:offset + 48 + bitmap_size] == bytes(bitmap_size)
        assert data[offset + 48 + bitmap_size:offset + length] == b'\xff' * bitmap_size
        end = offset + length
    assert end == len(data), 'truncated or unexpected trailing data'
    print(f'PASS: ICO structure, XOR pixels and AND masks at {len(SIZES)} sizes.')


def bind(dll, name, result, *args):
    fn = getattr(dll, name)
    fn.restype = result
    fn.argtypes = args
    return fn


class WindowsRenderer:
    def __init__(self):
        user = c.WinDLL('user32', use_last_error=True)
        gdi = c.WinDLL('gdi32', use_last_error=True)
        comctl = c.WinDLL('comctl32', use_last_error=True)
        ole = c.WinDLL('ole32')
        ptr, uint, integer = c.c_void_p, w.UINT, c.c_int
        self.load = bind(user, 'LoadImageW', ptr, ptr, w.LPCWSTR, uint, integer, integer, uint)
        self.destroy_icon = bind(user, 'DestroyIcon', w.BOOL, ptr)
        self.create_icon = bind(user, 'CreateIconFromResourceEx', ptr, ptr, w.DWORD,
                                w.BOOL, w.DWORD, integer, integer, uint)
        self.draw = bind(user, 'DrawIconEx', w.BOOL, ptr, integer, integer, ptr,
                         integer, integer, uint, ptr, uint)
        self.create_dc = bind(gdi, 'CreateCompatibleDC', ptr, ptr)
        self.delete_dc = bind(gdi, 'DeleteDC', w.BOOL, ptr)
        self.dib = bind(gdi, 'CreateDIBSection', ptr, ptr, ptr, uint, c.POINTER(ptr), ptr, w.DWORD)
        self.select = bind(gdi, 'SelectObject', ptr, ptr, ptr)
        self.delete_object = bind(gdi, 'DeleteObject', w.BOOL, ptr)
        self.flush = bind(gdi, 'GdiFlush', w.BOOL)
        self.il_create = bind(comctl, 'ImageList_Create', ptr, integer, integer, uint, integer, integer)
        self.il_destroy = bind(comctl, 'ImageList_Destroy', w.BOOL, ptr)
        self.il_add = bind(comctl, 'ImageList_ReplaceIcon', integer, ptr, integer, ptr)
        self.il_overlay = bind(comctl, 'ImageList_SetOverlayImage', w.BOOL, ptr, integer, integer)
        self.il_draw = bind(comctl, 'ImageList_Draw', w.BOOL, ptr, integer, ptr, integer, integer, uint)
        self.il_write = bind(comctl, 'ImageList_Write', w.BOOL, ptr, ptr)
        self.il_read = bind(comctl, 'ImageList_Read', ptr, ptr)
        self.stream = bind(ole, 'CreateStreamOnHGlobal', c.c_long, ptr, w.BOOL, c.POINTER(ptr))

    def round_trip(self, images):
        stream = c.c_void_p()
        assert self.stream(None, True, c.byref(stream)) == 0
        vtable = c.cast(stream, c.POINTER(c.POINTER(c.c_void_p))).contents
        release = c.WINFUNCTYPE(w.ULONG, c.c_void_p)(vtable[2])
        seek = c.WINFUNCTYPE(c.c_long, c.c_void_p, c.c_longlong, w.DWORD, c.c_void_p)(vtable[5])
        try:
            assert self.il_write(images, stream), 'ImageList_Write'
            assert seek(stream, 0, 0, None) == 0, 'IStream.Seek'
            restored = self.il_read(stream)
            assert restored, 'ImageList_Read'
            return restored
        finally:
            release(stream)

    def verify(self, path, size):
        icon = self.load(None, str(path), 1, size, size, 0x10)
        assert icon, f'LoadImageW({size})'
        dc = self.create_dc(None)
        pixels_ptr = c.c_void_p()
        header = c.create_string_buffer(struct.pack('<IiiHHIIiiII',
            40, size, -size, 1, 32, 0, size * size * 4, 0, 0, 0, 0))
        bitmap = self.dib(dc, header, 0, c.byref(pixels_ptr), None, 0)
        assert dc and bitmap
        old = self.select(dc, bitmap)
        pixels = (c.c_uint32 * (size * size)).from_address(pixels_ptr.value)
        background = [0xff000000 | ((i * 123457 + 0x204060) & 0xffffff)
                      for i in range(size * size)]
        images = base = restored = None

        def rgb():
            self.flush()
            return [p & 0xffffff for p in pixels]

        try:
            pixels[:] = background
            assert self.draw(dc, 0, 0, icon, size, size, 0, None, 3)
            assert rgb() == [p & 0xffffff for p in background], f'DrawIconEx altered RGB at {size}px'

            # Patterned opaque base icon, then add the blank as image-list overlay 1.
            xor = b''.join(struct.pack('<I', p ^ 0x00a55aa5) for p in background)
            mask = bytes(((size + 31) // 32) * 4 * size)
            resource = c.create_string_buffer(struct.pack('<IiiHHIIiiII',
                40, size, size * 2, 1, 32, 0, len(xor) + len(mask), 0, 0, 0, 0) + xor + mask)
            base = self.create_icon(resource, len(resource) - 1, True, 0x30000, size, size, 0)
            assert base, 'create patterned base icon'
            images = self.il_create(size, size, 0x21, 2, 1)  # ILC_COLOR32 | ILC_MASK
            assert images
            assert self.il_add(images, -1, base) == 0
            assert self.il_add(images, -1, icon) == 1
            assert self.il_overlay(images, 1, 1)
            pixels[:] = background
            assert self.il_draw(images, 0, dc, 0, 0, 1)
            expected = rgb()
            assert expected != [p & 0xffffff for p in background], 'test base must be visible'
            pixels[:] = background
            assert self.il_draw(images, 0, dc, 0, 0, 0x101)
            assert rgb() == expected, f'overlay damaged the base icon at {size}px'

            # Exercise the image-list persistence path used by icon caches.
            restored = self.round_trip(images)
            assert self.il_overlay(restored, 1, 1)
            pixels[:] = background
            assert self.il_draw(restored, 0, dc, 0, 0, 0x101)
            assert rgb() == expected, f'cached overlay damaged the base icon at {size}px'
        finally:
            for image_list in (restored, images):
                if image_list:
                    self.il_destroy(image_list)
            if base:
                self.destroy_icon(base)
            self.select(dc, old)
            self.delete_object(bitmap)
            self.delete_dc(dc)
            self.destroy_icon(icon)


def main():
    path = Path(sys.argv[1]).resolve()
    verify_format(path)
    renderer = WindowsRenderer()
    # Include sizes absent from the ICO to cover Windows' fallback scaling too.
    sizes = sorted(set(SIZES + (18, 28, 36, 60, 72, 192)))
    for size in sizes:
        renderer.verify(path, size)
    print(f'PASS: DrawIconEx, image-list overlay and cache round-trip at {len(sizes)} sizes.')


if __name__ == '__main__':
    main()
