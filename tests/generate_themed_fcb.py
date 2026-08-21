#!/usr/bin/env python3
# azul
# Copyright © 2016-2026 Ken Arroyo Ohori
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

"""Generates tests/Fixtures/themed.fcb, a FlatCityBuf file whose content
mirrors tests/Fixtures/themed.city.json (attributes, two LoDs, semantic
surfaces, a material theme and a texture theme). The test suite asserts that
both parsers produce identical output.

Implements just enough of the FlatBuffers wire format for azul's
FCBParsingHelper.hpp: tables, vtables, strings, scalar/struct/table vectors.
"""

import struct

class Builder:
    def __init__(self):
        self.buf = bytearray()
        self.vt = None
        self.obj_end = 0

    def head(self):
        return len(self.buf)

    def prep(self, size, extra):
        align = ((~(self.head() + extra)) + 1) & (size - 1)
        self.buf[0:0] = b'\0' * align

    def place(self, fmt, v):
        self.buf[0:0] = struct.pack(fmt, v)

    def push(self, fmt, v):
        self.prep(struct.calcsize(fmt), 0)
        self.place(fmt, v)

    def create_string(self, s):
        e = s.encode('utf-8')
        self.prep(4, len(e) + 1)
        self.place('<B', 0)
        self.buf[0:0] = e
        self.place('<I', len(e))
        return self.head()

    def u32_vector(self, values):
        self.prep(4, 4 * len(values))
        for v in reversed(values):
            self.place('<I', v)
        self.place('<I', len(values))
        return self.head()

    def blob_vector(self, payload):
        # [ubyte] vector used for attribute blobs
        self.prep(4, len(payload))
        self.buf[0:0] = payload
        self.place('<I', len(payload))
        return self.head()

    def struct_vector(self, packed_elems, elem_size, align):
        self.prep(4, elem_size * len(packed_elems))
        self.prep(align, elem_size * len(packed_elems))
        for pb in reversed(packed_elems):
            self.buf[0:0] = pb
        self.place('<I', len(packed_elems))
        return self.head()

    def offset_vector(self, handles):
        self.prep(4, 4 * len(handles))
        for h in reversed(handles):
            self.prep(4, 0)
            self.place('<I', self.head() - h + 4)
        self.place('<I', len(handles))
        return self.head()

    def start_table(self, num_slots):
        self.vt = [0] * num_slots
        self.obj_end = self.head()

    def __slot(self, slot):
        self.vt[slot] = self.head()

    def add_scalar(self, slot, fmt, value, default):
        if value == default:
            return
        self.push(fmt, value)
        self.__slot(slot)

    def add_struct(self, slot, packed, align):
        self.prep(align, len(packed))
        self.buf[0:0] = packed
        self.__slot(slot)

    def add_offset(self, slot, handle):
        if handle == 0:
            return
        # Prep first so any alignment padding is included in the relative
        # offset (padding shifts earlier bytes around).
        self.prep(4, 0)
        self.place('<I', self.head() - handle + 4)
        self.__slot(slot)

    def end_table(self):
        self.push('<i', 0)  # placeholder soffset to the vtable
        object_offset = self.head()
        # Trim trailing zero slots
        n = len(self.vt)
        while n > 0 and self.vt[n - 1] == 0:
            n -= 1
        vt = self.vt[:n]
        # Vtable entries (offset from table start to field), highest slot first
        for i in reversed(range(len(vt))):
            off = object_offset - vt[i] if vt[i] != 0 else 0
            self.prep(2, 0)
            self.place('<H', off)
        self.prep(2, 0)
        self.place('<H', object_offset - self.obj_end)          # table size
        self.prep(2, 0)
        self.place('<H', 4 + 2 * len(vt))                       # vtable size
        # Backpatch the soffset at the table start to point at the vtable
        stored = self.head() - object_offset
        start = self.head() - object_offset
        self.buf[start:start + 4] = struct.pack('<i', stored)
        return object_offset

    def finish(self, root_handle):
        self.prep(4, 0)
        self.place('<I', self.head() - root_handle + 4)
        return bytes(self.buf)


# ---------------------------------------------------------------------------
# Schema field indices (must match FCBParsingHelper.hpp)
# ---------------------------------------------------------------------------

HEADER_TRANSFORM, HEADER_APPEARANCE, HEADER_COLUMNS, HEADER_SEMANTIC_COLUMNS = 0, 1, 2, 3
HEADER_FEATURES_COUNT, HEADER_INDEX_NODE_SIZE = 4, 5

APPEARANCE_MATERIALS, APPEARANCE_TEXTURES, APPEARANCE_VERTICES_TEXTURE = 0, 1, 2
APPEARANCE_DEFAULT_THEME_TEXTURE, APPEARANCE_DEFAULT_THEME_MATERIAL = 3, 4

MATERIAL_NAME, MATERIAL_DIFFUSE_COLOR, MATERIAL_TRANSPARENCY = 0, 2, 6
TEXTURE_IMAGE = 1
COLUMN_INDEX, COLUMN_NAME, COLUMN_TYPE = 0, 1, 2

FEATURE_OBJECTS, FEATURE_VERTICES, FEATURE_APPEARANCE = 1, 2, 3

CITY_OBJECT_TYPE, CITY_OBJECT_EXTENSION_TYPE, CITY_OBJECT_ID = 0, 1, 2
CITY_OBJECT_GEOMETRY, CITY_OBJECT_ATTRIBUTES, CITY_OBJECT_COLUMNS = 4, 6, 7

GEOMETRY_TYPE, GEOMETRY_LOD = 0, 1
GEOMETRY_SHELLS, GEOMETRY_SURFACES, GEOMETRY_STRINGS, GEOMETRY_BOUNDARIES = 3, 4, 5, 6
GEOMETRY_SEMANTICS, GEOMETRY_SEMANTICS_OBJECTS, GEOMETRY_MATERIAL, GEOMETRY_TEXTURE = 7, 8, 9, 10

SEMANTIC_OBJECT_TYPE = 0

MATERIAL_MAPPING_THEME, MATERIAL_MAPPING_VERTICES, MATERIAL_MAPPING_VALUE = 0, 3, 4
TEXTURE_MAPPING_THEME, TEXTURE_MAPPING_SURFACES, TEXTURE_MAPPING_STRINGS = 0, 3, 4
TEXTURE_MAPPING_VERTICES = 5

GEOMETRY_TYPE_MULTISURFACE = 2
COLUMN_TYPE_STRING = 11

# Enumerators matching FCBParsingHelper's name tables
CITY_OBJECT_BUILDING = 6
SEMANTIC_ROOF, SEMANTIC_GROUND, SEMANTIC_WALL = 0, 1, 2


def make_column(b, index, name, col_type):
    name_handle = b.create_string(name)
    b.start_table(3)
    b.add_scalar(COLUMN_INDEX, '<H', index, 0)
    b.add_offset(COLUMN_NAME, name_handle)
    b.add_scalar(COLUMN_TYPE, '<B', col_type, 0)
    return b.end_table()


def make_material(b, diffuse, transparency=None):
    # diffuse colour is a vector of three doubles
    b.prep(8, 24)
    for d in reversed(diffuse):
        b.place('<d', d)
    b.place('<I', 3)
    color_handle = b.head()
    b.start_table(7)
    b.add_offset(MATERIAL_DIFFUSE_COLOR, color_handle)
    if transparency is not None:
        b.add_scalar(MATERIAL_TRANSPARENCY, '<d', transparency, 0.0)
    return b.end_table()


def make_texture(b, image):
    image_handle = b.create_string(image)
    b.start_table(2)
    b.add_offset(TEXTURE_IMAGE, image_handle)
    return b.end_table()


def make_appearance(b, materials, textures, texture_uvs, default_theme_texture, default_theme_material):
    material_handles = [make_material(b, d, t) for d, t in materials]
    texture_handles = [make_texture(b, img) for img in textures]
    uv_packed = [struct.pack('<dd', u, v) for u, v in texture_uvs]
    uv_vector = b.struct_vector(uv_packed, 16, 8)
    theme_texture_handle = b.create_string(default_theme_texture)
    theme_material_handle = b.create_string(default_theme_material)
    materials_vector = b.offset_vector(material_handles)
    textures_vector = b.offset_vector(texture_handles)
    b.start_table(5)
    b.add_offset(APPEARANCE_MATERIALS, materials_vector)
    b.add_offset(APPEARANCE_TEXTURES, textures_vector)
    b.add_offset(APPEARANCE_VERTICES_TEXTURE, uv_vector)
    b.add_offset(APPEARANCE_DEFAULT_THEME_TEXTURE, theme_texture_handle)
    b.add_offset(APPEARANCE_DEFAULT_THEME_MATERIAL, theme_material_handle)
    return b.end_table()


def make_semantic_object(b, semantic_type):
    b.start_table(1)
    b.add_scalar(SEMANTIC_OBJECT_TYPE, '<B', semantic_type, 0)
    return b.end_table()


def make_material_mapping(b, theme, shared_value=None, values=None):
    theme_handle = b.create_string(theme)
    values_handle = b.u32_vector(values) if values is not None else 0
    b.start_table(5)
    b.add_offset(MATERIAL_MAPPING_THEME, theme_handle)
    if values is not None:
        b.add_offset(MATERIAL_MAPPING_VERTICES, values_handle)
    if shared_value is not None:
        b.add_scalar(MATERIAL_MAPPING_VALUE, '<I', shared_value, 0)
    return b.end_table()


def make_texture_mapping(b, theme, surfaces, strings, values):
    theme_handle = b.create_string(theme)
    surfaces_handle = b.u32_vector(surfaces)
    strings_handle = b.u32_vector(strings)
    values_handle = b.u32_vector(values)
    b.start_table(6)
    b.add_offset(TEXTURE_MAPPING_THEME, theme_handle)
    b.add_offset(TEXTURE_MAPPING_SURFACES, surfaces_handle)
    b.add_offset(TEXTURE_MAPPING_STRINGS, strings_handle)
    b.add_offset(TEXTURE_MAPPING_VERTICES, values_handle)
    return b.end_table()


def make_geometry(b, lod, surface_rings, semantics_values, semantics_types,
                  material_mapping, texture_mapping):
    """surface_rings: list of surfaces, each a list of rings of vertex indices."""
    lod_handle = b.create_string(lod)
    surfaces = [len(rings) for rings in surface_rings]
    strings = [len(ring) for rings in surface_rings for ring in rings]
    boundaries = [v for rings in surface_rings for ring in rings for v in ring]
    shells_handle = b.u32_vector([len(surface_rings)])  # redundant level
    surfaces_handle = b.u32_vector(surfaces)
    strings_handle = b.u32_vector(strings)
    boundaries_handle = b.u32_vector(boundaries)
    semantics_handle = b.u32_vector(semantics_values)
    semantic_objects = b.offset_vector([make_semantic_object(b, t) for t in semantics_types])
    material_vector = b.offset_vector([material_mapping])
    texture_vector = b.offset_vector([texture_mapping])
    b.start_table(11)
    b.add_scalar(GEOMETRY_TYPE, '<B', GEOMETRY_TYPE_MULTISURFACE, 0)
    b.add_offset(GEOMETRY_LOD, lod_handle)
    b.add_offset(GEOMETRY_SHELLS, shells_handle)
    b.add_offset(GEOMETRY_SURFACES, surfaces_handle)
    b.add_offset(GEOMETRY_STRINGS, strings_handle)
    b.add_offset(GEOMETRY_BOUNDARIES, boundaries_handle)
    b.add_offset(GEOMETRY_SEMANTICS, semantics_handle)
    b.add_offset(GEOMETRY_SEMANTICS_OBJECTS, semantic_objects)
    b.add_offset(GEOMETRY_MATERIAL, material_vector)
    b.add_offset(GEOMETRY_TEXTURE, texture_vector)
    return b.end_table()


def make_city_object(b, obj_type, obj_id, attributes_blob, geometry_handles):
    id_handle = b.create_string(obj_id)
    attributes_handle = b.blob_vector(attributes_blob) if attributes_blob else 0
    geometry_vector = b.offset_vector(geometry_handles)
    b.start_table(8)
    b.add_scalar(CITY_OBJECT_TYPE, '<B', obj_type, 0)
    b.add_offset(CITY_OBJECT_ID, id_handle)
    b.add_offset(CITY_OBJECT_GEOMETRY, geometry_vector)
    b.add_offset(CITY_OBJECT_ATTRIBUTES, attributes_handle)
    return b.end_table()


def encode_attribute_string(column_index, value):
    encoded = value.encode('utf-8')
    return struct.pack('<HI', column_index, len(encoded)) + encoded


def main():
    vertices = [
        (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),       # ground quad
        (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1),       # roof quad
    ]

    # Feature buffer (its own size-prefixed FlatBuffer)
    fb = Builder()
    geom_lod2 = make_geometry(
        fb, "2",
        [[[4, 5, 6, 7]], [[0, 1, 5, 4]]],
        [0, 1], [SEMANTIC_WALL, SEMANTIC_ROOF],
        make_material_mapping(fb, "TestTheme", values=[0, 0]),
        make_texture_mapping(fb, "TestTheme", surfaces=[1, 1], strings=[5, 5],
                             values=[0, 0, 1, 2, 3, 0, 0, 1, 2, 3]))
    geom_lod1 = make_geometry(
        fb, "1",
        [[[0, 1, 2, 3]]],
        [0], [SEMANTIC_GROUND],
        # A shared value of 0 is indistinguishable from an absent field (the
        # writer omits schema defaults), so use per-surface values instead.
        make_material_mapping(fb, "TestTheme", values=[0]),
        make_texture_mapping(fb, "TestTheme", surfaces=[1], strings=[5],
                             values=[0, 0, 1, 2, 3]))
    city_object = make_city_object(
        fb, CITY_OBJECT_BUILDING, "bld-1",
        encode_attribute_string(0, "office"),
        [geom_lod1, geom_lod2])
    vertex_packed = [struct.pack('<iii', x, y, z) for x, y, z in vertices]
    feature_vertices = fb.struct_vector(vertex_packed, 12, 4)
    objects_vector = fb.offset_vector([city_object])
    fb.start_table(4)
    fb.add_offset(FEATURE_OBJECTS, objects_vector)
    fb.add_offset(FEATURE_VERTICES, feature_vertices)
    feature = fb.end_table()
    feature_bytes = fb.finish(feature)

    # Header buffer (a separate size-prefixed FlatBuffer)
    hb = Builder()
    appearance = make_appearance(
        hb,
        materials=[((1.0, 0.0, 0.0), 0.5), ((0.0, 1.0, 0.0), None)],
        textures=["facade.png"],
        texture_uvs=[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)],
        default_theme_texture="TestTheme",
        default_theme_material="TestTheme")
    columns = hb.offset_vector([make_column(hb, 0, "function", COLUMN_TYPE_STRING)])
    transform = struct.pack('<dddddd', 1.0, 1.0, 1.0, 0.0, 0.0, 0.0)
    hb.start_table(28)
    hb.add_struct(HEADER_TRANSFORM, transform, 8)
    hb.add_offset(HEADER_APPEARANCE, appearance)
    hb.add_offset(HEADER_COLUMNS, columns)
    hb.add_scalar(HEADER_FEATURES_COUNT, '<Q', 1, 0)
    hb.add_scalar(HEADER_INDEX_NODE_SIZE, '<H', 16, 0)
    header = hb.end_table()
    header_buffer = hb.finish(header)

    # File layout: magic, size-prefixed header, packed Hilbert R-tree
    # (skipped by azul, but its byte length is computed from the header:
    # ceil-divide the node count down to one root, 40 bytes per node),
    # then features. The size prefix counts the header FlatBuffer only;
    # azul computes featureBegin as 12 + headerSize + rtree + attrIndex.
    rtree_size = 80  # features_count=1, index_node_size=16 -> 2 nodes * 40
    out = bytearray()
    out += b'fcb\x01fcb\x00'
    out += struct.pack('<I', len(header_buffer))
    out += header_buffer
    out += b'\0' * rtree_size
    out += struct.pack('<I', len(feature_bytes))
    out += feature_bytes

    with open('tests/Fixtures/themed.fcb', 'wb') as f:
        f.write(out)
    print(f"Wrote tests/Fixtures/themed.fcb ({len(out)} bytes)")


if __name__ == '__main__':
    main()
