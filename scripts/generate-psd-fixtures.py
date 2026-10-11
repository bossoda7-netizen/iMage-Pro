"""Generate small PSD compatibility fixtures without third-party packages.

The fixtures exercise the PSD reader's raw, RLE, ZIP and ZIP-prediction
decoders, layer visibility and folder divider handling. The generator uses
only Python's standard library so the test suite has no external PSD package
dependency or upstream fixture provenance.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "Tests/ImageProTests/Fixtures"
WIDTH, HEIGHT = 32, 24


def be(value: int, size: int) -> bytes:
    return value.to_bytes(size, "big", signed=value < 0)


def pascal(value: str, alignment: int = 4) -> bytes:
    raw = value.encode("mac_roman", errors="replace")[:255]
    result = bytes([len(raw)]) + raw
    result += b"\0" * ((alignment - len(result) % alignment) % alignment)
    return result


def packbits_row(row: bytes) -> bytes:
    result = bytearray()
    for start in range(0, len(row), 128):
        chunk = row[start : start + 128]
        result.append(len(chunk) - 1)
        result.extend(chunk)
    return bytes(result)


def encode_plane(plane: bytes, width: int, height: int, compression: str) -> bytes:
    rows = [plane[y * width : (y + 1) * width] for y in range(height)]
    if compression == "RAW":
        return be(0, 2) + plane
    if compression == "RLE":
        encoded = [packbits_row(row) for row in rows]
        return be(1, 2) + b"".join(be(len(row), 2) for row in encoded) + b"".join(encoded)
    if compression == "ZIP":
        return be(2, 2) + zlib.compress(plane)
    if compression == "ZIP_WITH_PREDICTION":
        predicted = bytearray()
        for row in rows:
            predicted.append(row[0])
            predicted.extend((row[x] - row[x - 1]) & 0xFF for x in range(1, width))
        return be(3, 2) + zlib.compress(bytes(predicted))
    raise ValueError(compression)


def tagged_section(section: int) -> bytes:
    return b"8BIMlsct" + be(12, 4) + be(section, 4) + b"8BIMpass"


def record(
    name: str,
    rect: tuple[int, int, int, int],
    channels: list[tuple[int, bytes]],
    section: int = 0,
    visible: bool = True,
    opacity: int = 255,
) -> tuple[bytes, bytes]:
    top, left, bottom, right = rect
    result = bytearray(struct.pack(">iiiiH", top, left, bottom, right, len(channels)))
    for channel_id, encoded in channels:
        result.extend(struct.pack(">hi", channel_id, len(encoded)))
    result.extend(b"8BIMnorm")
    result.extend(bytes([opacity, 0, 0 if visible else 2, 0]))
    extra = bytearray(be(0, 4) + be(0, 4) + pascal(name))
    unicode_name = name.encode("utf-16-be")
    unicode_block = be(len(name), 4) + unicode_name
    extra.extend(b"8BIMluni" + be(len(unicode_block), 4) + unicode_block)
    if len(unicode_block) % 2:
        extra.append(0)
    if section:
        extra.extend(tagged_section(section))
    result.extend(be(len(extra), 4))
    result.extend(extra)
    return bytes(result), b"".join(encoded for _, encoded in channels)


def color_planes(width: int, height: int, color: tuple[int, int, int, int]) -> list[bytes]:
    return [bytes([color[index]] * (width * height)) for index in range(4)]


def make_psd(records: list[tuple[bytes, bytes]], width: int = WIDTH, height: int = HEIGHT) -> bytes:
    layer_info = bytearray(be(-len(records), 2))
    for layer, _ in records:
        layer_info.extend(layer)
    for _, data in records:
        layer_info.extend(data)
    layer_mask = be(len(layer_info), 4) + bytes(layer_info) + be(0, 4)
    header = b"8BPS" + be(1, 2) + b"\0" * 6 + be(4, 2)
    header += be(height, 4) + be(width, 4) + be(8, 2) + be(3, 2)
    header += be(0, 4) + be(0, 4)
    header += be(len(layer_mask), 4) + layer_mask
    header += be(0, 2) + bytes(width * height * 4)
    return header


def raster_record(
    name: str,
    x: int,
    y: int,
    width: int,
    height: int,
    color: tuple[int, int, int, int],
    compression: str,
    visible: bool = True,
    opacity: int = 255,
) -> tuple[bytes, bytes]:
    planes = color_planes(width, height, color)
    channels = [
        (channel_id, encode_plane(plane, width, height, compression))
        for channel_id, plane in zip((0, 1, 2, -1), planes)
    ]
    return record(
        name,
        (y, x, y + height, x + width),
        channels,
        visible=visible,
        opacity=opacity,
    )


def fixture_layers(compression: str) -> list[tuple[bytes, bytes]]:
    blue = raster_record("底图", 0, 0, WIDTH, HEIGHT, (0, 0, 255, 255), compression)
    red = raster_record("半透明红", 4, 3, 8, 6, (255, 0, 0, 128), compression, opacity=192)
    group = record("设计分组", (0, 0, 0, 0), [], section=1)
    end = record("</Layer group>", (0, 0, 0, 0), [], section=3)
    green = raster_record("绿色", 21, 16, 5, 4, (0, 255, 0, 255), compression)
    # PSD records are stored bottom-to-top; the reader reverses them for the UI.
    return [blue, end, red, group, green]


def hidden_layer_fixture() -> bytes:
    base = raster_record("底图", 0, 0, WIDTH, HEIGHT, (0, 0, 255, 255), "ZIP")
    hidden = raster_record("隐藏图层", 4, 3, 8, 6, (255, 0, 0, 255), "ZIP", visible=False)
    return make_psd([base, hidden])


def hidden_group_fixture() -> bytes:
    base = raster_record("底图", 0, 0, WIDTH, HEIGHT, (0, 0, 255, 255), "ZIP")
    child = raster_record("文件夹内容", 4, 3, 8, 6, (255, 0, 0, 255), "ZIP")
    end = record("</Layer group>", (0, 0, 0, 0), [], section=3)
    group = record("隐藏文件夹", (0, 0, 0, 0), [], section=1, visible=False)
    return make_psd([base, end, child, group])


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for compression in ("RAW", "RLE", "ZIP", "ZIP_WITH_PREDICTION"):
        (ROOT / f"fixture-{compression}.psd").write_bytes(make_psd(fixture_layers(compression)))
    (ROOT / "hidden-layer.psd").write_bytes(hidden_layer_fixture())
    (ROOT / "hidden-groups.psd").write_bytes(hidden_group_fixture())


if __name__ == "__main__":
    main()
