"""Verify ICO masks and Windows rendering without touching the desktop/settings.

Usage: python tests/verify_overlay.py <generated-icon.ico>
Only uses the Python standard library and off-screen Windows GDI objects.
"""

import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import struct
import sys


SIZES = (16, 20, 24, 28, 32, 36, 40, 48, 56, 60, 64, 72, 80, 96,
         112, 120, 128, 144, 160, 192, 224, 240, 256)


def verify_format(path):
    data = path.read_bytes()
    assert struct.unpack_from('<HHH', data) == (0, 1, len(SIZES))
    end = 6 + 16 * len(SIZES)
    for i, size in enumerate(SIZES):
        width, height, colors, reserved, planes, bpp, length, offset = struct.unpack_from(
            '<BBBBHHII', data, 6 + i * 16)
        assert (width or 256, height or 256, colors, reserved, planes, bpp) == (
            size, size, 0, 0, 1, 32)
        color_size = size * size * 4
        mask_size = ((size + 31) // 32) * 4 * size
        assert offset == end and length == 40 + color_size + mask_size
        assert struct.unpack_from('<IiiHHIIiiII', data, offset) == (
            40, size, size * 2, 1, 32, 0, color_size + mask_size, 0, 0, 0, 0)
        anchor = max(2, (size + 15) // 16)
        expected_pixels = bytearray(color_size)
        expected_mask = bytearray(b'\xff' * mask_size)
        mask_stride = ((size + 31) // 32) * 4
        for y in range(anchor):
            for x in range(anchor):
                expected_pixels[(y * size + x) * 4 + 3] = 1
                expected_mask[y * mask_stride + x // 8] &= ~(0x80 >> (x % 8))
        assert data[offset + 40:offset + 40 + color_size] == expected_pixels
        assert data[offset + 40 + color_size:offset + length] == expected_mask
        end = offset + length
    assert end == len(data), 'truncated or unexpected trailing data'
    print(f'PASS: ARGB structure, nonzero alpha anchor and matching AND masks at {len(SIZES)} sizes.')


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
        self.il_get_icon = bind(comctl, 'ImageList_GetIcon', ptr, ptr, integer, uint)
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

        def rgba():
            self.flush()
            return list(pixels)

        def assert_safe(actual, expected, label):
            # Tiny anchor blending may change a few RGB values by one level.
            # Alpha loss is never allowed: that is what created the cut-outs.
            assert all((a >> 24) == (b >> 24) for a, b in zip(actual, expected)), f'{label}: alpha damaged at {size}px'
            changed = sum(a != b for a, b in zip(actual, expected))
            max_changed = max(64, ((size + 15) // 16 + 1) ** 2)
            assert changed <= max_changed, f'{label}: too many altered pixels at {size}px'
            assert all(abs(((a >> shift) & 255) - ((b >> shift) & 255)) <= 1
                       for a, b in zip(actual, expected) for shift in (0, 8, 16)), f'{label}: RGB damaged at {size}px'

        def verify_extracted(image_list):
            extracted = self.il_get_icon(image_list, 1, 1)
            assert extracted
            try:
                pixels[:] = background
                assert self.draw(dc, 0, 0, extracted, size, size, 0, None, 3)
                assert_safe(rgba(), background, 'extracted overlay')
            finally:
                self.destroy_icon(extracted)

        try:
            pixels[:] = background
            assert self.draw(dc, 0, 0, icon, size, size, 0, None, 3)
            assert_safe(rgba(), background, 'DrawIconEx')

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
            expected = rgba()
            assert expected != background, 'test base must be visible'
            pixels[:] = background
            assert self.il_draw(images, 0, dc, 0, 0, 0x101)
            assert_safe(rgba(), expected, 'composed overlay')
            verify_extracted(images)

            # Exercise the image-list persistence path used by icon caches.
            restored = self.round_trip(images)
            assert self.il_overlay(restored, 1, 1)
            pixels[:] = background
            assert self.il_draw(restored, 0, dc, 0, 0, 0x101)
            assert_safe(rgba(), expected, 'cached overlay')
            verify_extracted(restored)
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
    sizes = sorted(set(SIZES + (18, 22, 30, 45, 54, 66, 90, 150, 300)))
    for size in sizes:
        renderer.verify(path, size)
    print(f'PASS: RGBA preservation, image-list extraction/composition and cache round-trip at {len(sizes)} sizes.')


if __name__ == '__main__':
    main()
