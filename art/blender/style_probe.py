"""
Crazy Little Worm - art style look-dev probe generator.

Builds ONE comparison scene containing 4 candidate art directions
(rows) x 3 probes (columns), so we can pick a direction by looking
rather than by arguing.

  Rows (styles)                Columns (probes)
  A  Chunky Toybox             1  Gate + guest queue (tell legibility)
  B  Hand-Painted Stylized     2  Palette + material board
  C  Vector Flat / Paper       3  Carousel (day-1 hero ride)
  D  Stylized Semi-Real

Baseline mood is locked to CHEERFUL: bright sun, blue sky, candy palette.
All horror comes from the anomalies, never from the park.

Units: 1 Blender unit == 1 Roblox stud. A guest is ~5 studs tall,
matching an R15 character, so silhouettes read at true in-game scale.

Regenerate from Blender:
    exec(open(r"<repo>/art/blender/style_probe.py").read())
"""

import bpy
import math
import os
from mathutils import Vector

# --------------------------------------------------------------------------
# Palette - cheerful candy baseline. These are the values under review.
# --------------------------------------------------------------------------

PAL = {
    # park furniture
    "BOOTH_BODY":   "#FFF3E0",
    "BOOTH_TRIM":   "#FF6B6B",
    "ROOF_A":       "#FF6B6B",
    "ROOF_B":       "#FFF5E1",
    "COUNTER":      "#C89666",
    "SIGN":         "#4ECDC4",
    "DARK":         "#2D3142",
    "GROUND":       "#7BC950",
    "PATH":         "#E8DCC8",
    # ordinary guests
    "SKIN":         "#F2C49B",
    "SHIRT_A":      "#5AA9E6",
    "SHIRT_B":      "#FF9FF3",
    "PANTS":        "#3D5A80",
    # anomaly tells
    "INFECT_SKIN":  "#A8C686",
    "INFECT_SHIRT": "#6B8F3D",
    "ALIEN_COAT":   "#3D405B",
    "GOLD":         "#FFC857",
    # rides
    "RIDE_A":       "#FF6B6B",
    "RIDE_B":       "#FFE66D",
    "RIDE_POLE":    "#E6E6E6",
    "HORSE":        "#FFF5E1",
}

# Per-slot surface response. Toybox/painted read these loosely; semi-real
# leans on them hard because that is the whole point of that direction.
ROUGH = {
    "RIDE_POLE": 0.25, "GOLD": 0.3, "SIGN": 0.45,
    "GROUND": 0.9, "PATH": 0.9, "COUNTER": 0.7,
}
METAL = {"RIDE_POLE": 0.9, "GOLD": 0.8}

# Anomaly tells we are stress-testing for readability at gate distance.
GUESTS = [
    # (x offset, kind)
    (9.0,  "normal_a"),
    (14.5, "infected"),
    (20.0, "normal_b"),
    (25.5, "alien"),
    (31.0, "cult"),
]

# A style is a FORM LANGUAGE first and a shader second. Each entry below
# changes proportion, part count and shape vocabulary - not just surfacing -
# because that is what actually distinguishes one art direction from another.
#
#   head        head cube size in studs (toy styles exaggerate it)
#   torso/arm/leg   block dimensions (x, y, z)
#   depth       y-axis squash; the paper style is deliberately card-thin
#   detail      how many parts a guest is built from
#   trim        how much decorative geometry buildings carry
STYLES = [
    dict(key="toybox", shader="toybox", label="A  CHUNKY TOYBOX",
         bevel=0.16, seg=2, cyl=16, smooth=False,
         head=1.80, torso=(2.45, 1.30, 1.80), arm=(0.90, 0.95, 1.50),
         leg=(1.00, 1.00, 1.45), arm_gap=1.70, leg_gap=0.60,
         depth=1.0, detail="low", trim="chunky"),

    dict(key="painted", shader="painted", label="B  HAND-PAINTED STYLIZED",
         bevel=0.07, seg=2, cyl=20, smooth=False,
         head=1.32, torso=(2.05, 1.10, 2.10), arm=(0.66, 0.76, 1.90),
         leg=(0.80, 0.86, 1.85), arm_gap=1.40, leg_gap=0.52,
         depth=1.0, detail="mid", trim="decorated"),

    dict(key="flat", shader="flat", label="C  VECTOR FLAT / PAPER",
         bevel=0.0, seg=0, cyl=8, smooth=False,
         head=1.55, torso=(2.60, 0.45, 2.35), arm=None,
         leg=(2.10, 0.45, 1.65), arm_gap=0.0, leg_gap=0.0,
         depth=0.42, detail="slab", trim="billboard"),

    dict(key="pbr", shader="pbr", label="D  STYLIZED SEMI-REAL",
         bevel=0.04, seg=3, cyl=32, smooth=True,
         head=1.08, torso=(1.85, 1.00, 2.25), arm=(0.54, 0.60, 1.00),
         leg=(0.72, 0.80, 1.15), arm_gap=1.22, leg_gap=0.44,
         depth=1.0, detail="high", trim="panelled"),

    # ---- THE LOCKED DIRECTION -------------------------------------------
    # A's oversized head (max surface for the infected skin tell) carrying
    # B's articulated limbs (hands + shoes, so guests can gesture - the
    # salt-rescue thumbs-up in game-design.md S4 needs arms). Depth comes
    # from AO baked into VERTEX COLOURS, not textures: no atlas, no UVs,
    # one material, and it survives export to a Roblox MeshPart.
    dict(key="clw", shader="vao", label="*  CRAZY LITTLE WORM  -  LOCKED",
         bevel=0.13, seg=2, cyl=16, smooth=False, vao=True,
         head=1.70, torso=(2.30, 1.20, 1.90), arm=(0.72, 0.82, 1.62),
         leg=(0.88, 0.92, 1.45), arm_gap=1.58, leg_gap=0.56,
         depth=1.0, detail="mid", trim="clw"),
]

# Bays are spaced far enough apart that each one's camera sits clear of the
# NEXT bay's backdrop wall. Backdrop depth (17) + camera pull-back (46) sets
# the floor on this number.
ROW_PITCH = 95.0     # world Y between style bays
PROBE_PALETTE_X = 46.0
PROBE_RIDE_X = 74.0


# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)


def mute(h, sat=0.45, val=0.88):
    """Push a candy colour toward a grounded, semi-real one."""
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    grey = 0.299 * r + 0.587 * g + 0.114 * b
    r = (grey + (r - grey) * sat) * val
    g = (grey + (g - grey) * sat) * val
    b = (grey + (b - grey) * sat) * val
    return "#%02X%02X%02X" % tuple(max(0, min(255, int(c * 255))) for c in (r, g, b))


# --------------------------------------------------------------------------
# Node helpers (Blender 4.x/5.x socket layout)
# --------------------------------------------------------------------------

def sock(sockets, name):
    """Pick the *enabled* socket of a given name (ShaderNodeMix reuses names)."""
    for s in sockets:
        if s.name == name and s.enabled:
            return s
    return sockets[name]


def set_in(node, key, val):
    if key in node.inputs:
        node.inputs[key].default_value = val


def mix_rgb(nt, blend, fac):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    sock(n.inputs, "Factor").default_value = fac
    return n


def mix_a(n):
    return sock(n.inputs, "A")


def mix_b(n):
    return sock(n.inputs, "B")


def mix_out(n):
    return sock(n.outputs, "Result")


def new_mat(name, viewport_hex):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = hexc(viewport_hex)      # solid-shading preview
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    return m, nt, out


# --------------------------------------------------------------------------
# The four shader treatments
# --------------------------------------------------------------------------

def mat_toybox(name, h, slot):
    """Flat-shaded plastic. Colour does all the work; bevels catch the sun."""
    m, nt, out = new_mat(name, h)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.location = (300, 0)
    set_in(p, "Base Color", hexc(h))
    set_in(p, "Roughness", ROUGH.get(slot, 0.55))
    set_in(p, "Metallic", 0.0)
    set_in(p, "Specular IOR Level", 0.22)
    nt.links.new(p.outputs[0], out.inputs[0])
    return m


def mat_painted(name, h, slot):
    """Fake hand-painted: colour grain + vertical baked-AO gradient + rim shade.

    Stands in for a real painted texture atlas. EEVEE has no Pointiness, so
    edge wear is approximated with Layer Weight rather than curvature.
    """
    m, nt, out = new_mat(name, h)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.location = (-1000, 0)

    # brush-grain colour variation
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.location = (-820, 180)
    set_in(noise, "Scale", 11.0)
    set_in(noise, "Detail", 6.0)
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    gramp = nt.nodes.new("ShaderNodeValToRGB")
    gramp.location = (-640, 180)
    gramp.color_ramp.elements[0].position = 0.34
    gramp.color_ramp.elements[0].color = (0.62, 0.62, 0.62, 1)
    gramp.color_ramp.elements[1].position = 0.70
    gramp.color_ramp.elements[1].color = (1.18, 1.18, 1.18, 1)
    nt.links.new(noise.outputs["Fac"], gramp.inputs["Fac"])

    # baked ambient occlusion faked as a vertical gradient (dark at the floor)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-820, -60)
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.location = (-640, -60)
    set_in(mr, "From Min", 0.0)
    set_in(mr, "From Max", 5.0)
    set_in(mr, "To Min", 0.55)
    set_in(mr, "To Max", 1.0)
    mr.clamp = True
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])

    # rim/edge shading
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.location = (-820, -300)
    set_in(lw, "Blend", 0.35)
    framp = nt.nodes.new("ShaderNodeValToRGB")
    framp.location = (-640, -300)
    framp.color_ramp.elements[0].position = 0.0
    framp.color_ramp.elements[0].color = (0.72, 0.72, 0.72, 1)
    framp.color_ramp.elements[1].position = 1.0
    framp.color_ramp.elements[1].color = (1.10, 1.10, 1.10, 1)
    nt.links.new(lw.outputs["Facing"], framp.inputs["Fac"])

    grain = mix_rgb(nt, "MULTIPLY", 0.30)
    grain.location = (-380, 100)
    mix_a(grain).default_value = hexc(h)
    nt.links.new(gramp.outputs["Color"], mix_b(grain))

    ao = mix_rgb(nt, "MULTIPLY", 0.85)
    ao.location = (-180, 40)
    nt.links.new(mix_out(grain), mix_a(ao))
    nt.links.new(mr.outputs["Result"], mix_b(ao))

    rim = mix_rgb(nt, "MULTIPLY", 0.60)
    rim.location = (40, -20)
    nt.links.new(mix_out(ao), mix_a(rim))
    nt.links.new(framp.outputs["Color"], mix_b(rim))

    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.location = (300, 0)
    nt.links.new(mix_out(rim), p.inputs["Base Color"])
    set_in(p, "Roughness", 0.78)
    set_in(p, "Specular IOR Level", 0.12)
    nt.links.new(p.outputs[0], out.inputs[0])
    return m


def mat_flat(name, h, slot):
    """Pure emission: unlit, unshaded, absolutely flat colour."""
    m, nt, out = new_mat(name, h)
    e = nt.nodes.new("ShaderNodeEmission")
    e.location = (300, 0)
    e.inputs["Color"].default_value = hexc(h)
    e.inputs["Strength"].default_value = 1.0
    nt.links.new(e.outputs[0], out.inputs[0])
    return m


def mat_pbr(name, h, slot):
    """Grounded materials: metal reads as metal, paint gets fine surface noise."""
    m, nt, out = new_mat(name, h)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.location = (300, 0)
    set_in(p, "Base Color", hexc(h))
    set_in(p, "Metallic", METAL.get(slot, 0.0))
    set_in(p, "Roughness", ROUGH.get(slot, 0.42))
    set_in(p, "Specular IOR Level", 0.5)

    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.location = (-620, -240)
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.location = (-440, -240)
    set_in(n, "Scale", 34.0)
    set_in(n, "Detail", 8.0)
    nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.location = (-180, -240)
    set_in(bump, "Strength", 0.14)
    nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])

    nt.links.new(p.outputs[0], out.inputs[0])
    return m


def mat_vao(name, h, slot):
    """THE PRODUCTION SHADER.

    Flat plastic like A, but multiplied by a baked ambient-occlusion term
    read from the mesh's "AO" vertex-colour layer. No image texture, no UVs,
    one material for the whole game. Roblox MeshParts carry vertex colours
    through FBX import, so the same depth ships in-engine.
    """
    m, nt, out = new_mat(name, h)
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.location = (-320, -140)
    attr.attribute_type = "GEOMETRY"
    attr.attribute_name = AO_LAYER

    ao = mix_rgb(nt, "MULTIPLY", 1.0)
    ao.location = (-60, 0)
    mix_a(ao).default_value = hexc(h)
    nt.links.new(attr.outputs["Color"], mix_b(ao))

    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.location = (300, 0)
    nt.links.new(mix_out(ao), p.inputs["Base Color"])
    set_in(p, "Roughness", ROUGH.get(slot, 0.55))
    set_in(p, "Metallic", METAL.get(slot, 0.0))
    set_in(p, "Specular IOR Level", 0.22)
    nt.links.new(p.outputs[0], out.inputs[0])
    return m


SHADERS = {
    "toybox": mat_toybox,
    "painted": mat_painted,
    "flat": mat_flat,
    "pbr": mat_pbr,
    "vao": mat_vao,
}


def build_palette(style):
    fn = SHADERS[style["shader"]]
    mats = {}
    for slot, h in PAL.items():
        col = mute(h) if style["key"] == "pbr" else h
        mats[slot] = fn("%s_%s" % (style["key"], slot), col, slot)
    return mats


# --------------------------------------------------------------------------
# Geometry helpers - built from pydata so nothing depends on bpy.ops context
# --------------------------------------------------------------------------

def _obj(name, verts, faces, mat, coll, smooth_range=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate(verbose=False)
    me.update()
    if smooth_range:
        lo, hi = smooth_range
        for i, poly in enumerate(me.polygons):
            poly.use_smooth = lo <= i < hi
    ob = bpy.data.objects.new(name, me)
    if mat:
        me.materials.append(mat)
    coll.objects.link(ob)
    return ob


AO_LAYER = "AO"

# AO curve constants - tuned by eye against bay B's procedural gradient.
AO_WORLD_TOP = 5.5      # studs; above this height nothing is occluded
AO_WORLD_FLOOR = 0.62   # darkest value at ground level
AO_LOCAL_FLOOR = 0.80   # extra darkening at each block's own underside


def bake_vertex_ao(ob):
    """Write a grey ambient-occlusion term into a per-vertex colour layer.

    Two terms multiplied:
      * world height - the park floor is dark, shoulders are lit
      * per-block height - every block darkens at its own underside, which
        is what actually separates an arm from the torso behind it

    This replaces a texture atlas. It is the whole reason the locked style
    can look like B while costing like A.
    """
    me = ob.data
    if not me.vertices:
        return
    zs = [v.co.z for v in me.vertices]
    zmin, zmax = min(zs), max(zs)
    span = max(zmax - zmin, 1e-4)

    if AO_LAYER not in me.color_attributes:
        me.color_attributes.new(name=AO_LAYER, type="FLOAT_COLOR",
                                domain="POINT")
    layer = me.color_attributes[AO_LAYER]
    for i, v in enumerate(me.vertices):
        world = min(max(v.co.z / AO_WORLD_TOP, 0.0), 1.0)
        local = (v.co.z - zmin) / span
        a = (AO_WORLD_FLOOR + (1.0 - AO_WORLD_FLOOR) * world) * \
            (AO_LOCAL_FLOOR + (1.0 - AO_LOCAL_FLOOR) * local)
        layer.data[i].color = (a, a, a, 1.0)


def bevel(ob, style):
    if style["bevel"] <= 0:
        return ob
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = style["bevel"]
    m.segments = style["seg"]
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    return ob


def box(name, center, size, mat, coll, style=None):
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    v = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    ob = _obj(name, v, f, mat, coll)
    if style:
        bevel(ob, style)
    return ob


def cyl(name, center, r, h, mat, coll, style=None, r_top=None, n=None):
    n = n or (style["cyl"] if style else 16)
    r_top = r if r_top is None else max(r_top, 0.001)
    cx, cy, cz = center
    zb, zt = cz - h / 2, cz + h / 2
    v = []
    for z, rad in ((zb, r), (zt, r_top)):
        for i in range(n):
            a = 2 * math.pi * i / n
            v.append((cx + rad * math.cos(a), cy + rad * math.sin(a), z))
    f = []
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    f.append(tuple(range(n - 1, -1, -1)))
    f.append(tuple(range(n, 2 * n)))
    smooth = (0, n) if (style and style["smooth"]) else None
    ob = _obj(name, v, f, mat, coll, smooth_range=smooth)
    if style:
        bevel(ob, style)
    return ob


def wedge(name, center, r_bot, r_top, h, a0, a1, mat, coll):
    """One canopy stripe panel."""
    cx, cy, cz = center
    zb, zt = cz - h / 2, cz + h / 2
    v = [
        (cx + r_bot * math.cos(a0), cy + r_bot * math.sin(a0), zb),
        (cx + r_bot * math.cos(a1), cy + r_bot * math.sin(a1), zb),
        (cx + r_top * math.cos(a1), cy + r_top * math.sin(a1), zt),
        (cx + r_top * math.cos(a0), cy + r_top * math.sin(a0), zt),
    ]
    return _obj(name, v, [(0, 1, 2, 3)], mat, coll)


def label(name, body, loc, size, mat, coll, align="LEFT", upright=False):
    """Captions lie flat on the ground by default so they read from the
    overview camera without polluting the skyline in bay close-ups."""
    cu = bpy.data.curves.new(name, type="FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    cu.extrude = 0.02
    ob = bpy.data.objects.new(name, cu)
    ob.location = loc
    ob.rotation_euler = (math.pi / 2, 0, 0) if upright else (0, 0, 0)
    cu.materials.append(mat)
    coll.objects.link(ob)
    return ob


# --------------------------------------------------------------------------
# Probe 1 - gate booth + guest queue (the tell-legibility test)
# --------------------------------------------------------------------------

def build_booth(style, M, ox, oy, coll):
    """The gate booth, rebuilt in each style's own shape vocabulary:
    chunky slabs / decorated fairground / flat billboard / panelled kiosk."""
    s = style
    t = s["trim"]
    k = s["key"]

    if t == "billboard":
        # paper style: the booth is a facade, not a volume
        box("booth_face_%s" % k, (ox, oy - 2.6, 3.2), (9.2, 0.5, 6.4),
            M["BOOTH_BODY"], coll, s)
        box("booth_side_%s" % k, (ox, oy, 3.0), (7.4, 5.4, 6.0),
            M["BOOTH_BODY"], coll, s)
        box("booth_win_%s" % k, (ox, oy - 2.9, 4.4), (5.4, 0.3, 2.2),
            M["DARK"], coll, s)
        box("booth_counter_%s" % k, (ox, oy - 3.0, 3.0), (9.2, 0.5, 0.5),
            M["COUNTER"], coll, s)
        box("booth_roof_%s" % k, (ox, oy - 1.6, 6.9), (10.4, 7.0, 1.0),
            M["ROOF_A"], coll, s)
        box("sign_%s" % k, (ox, oy - 2.9, 8.6), (7.0, 0.3, 2.6), M["SIGN"], coll, s)
        for i, dx in enumerate((5.2, 6.8)):
            box("stile_%s_%d" % (k, i), (ox + dx, oy - 3.0, 1.6),
                (0.4, 0.4, 3.2), M["RIDE_POLE"], coll, s)
        return

    body_h = 6.0
    box("booth_body_%s" % k, (ox, oy, body_h / 2), (8, 6, body_h),
        M["BOOTH_BODY"], coll, s)
    box("booth_base_%s" % k, (ox, oy, 0.35), (8.6, 6.6, 0.7), M["DARK"], coll, s)
    box("booth_counter_%s" % k, (ox, oy - 3.3, 4.1), (9.0, 1.4, 0.55),
        M["COUNTER"], coll, s)
    box("booth_window_%s" % k, (ox, oy - 3.05, 4.9), (5.2, 0.4, 2.4),
        M["DARK"], coll, s)

    if t == "clw":
        # locked style: A's fat confident roof, plus just enough of B's trim
        # (window frame, gold sign edge, planter) to keep large faces alive
        box("booth_roof_%s" % k, (ox, oy, 6.6), (9.8, 7.8, 1.1),
            M["BOOTH_TRIM"], coll, s)
        for i in range(6):
            mat = M["ROOF_A"] if i % 2 == 0 else M["ROOF_B"]
            box("awning_%s_%d" % (k, i), (ox - 4.0 + i * 1.6, oy - 4.2, 5.8),
                (1.6, 2.8, 0.44), mat, coll, s)
        for side, dx in (("l", -2.8), ("r", 2.8)):
            box("winframe_%s_%s" % (k, side), (ox + dx, oy - 3.1, 4.9),
                (0.36, 0.5, 2.8), M["BOOTH_TRIM"], coll, s)
        box("winsill_%s" % k, (ox, oy - 3.1, 3.5), (6.2, 0.5, 0.34),
            M["BOOTH_TRIM"], coll, s)
        box("planter_%s" % k, (ox - 4.8, oy - 2.4, 0.75), (1.5, 1.5, 1.5),
            M["COUNTER"], coll, s)
        box("shrub_%s" % k, (ox - 4.8, oy - 2.4, 2.05), (1.7, 1.7, 1.2),
            M["GROUND"], coll, s)
        box("sign_%s" % k, (ox, oy - 3.4, 8.3), (7.0, 0.6, 2.3), M["SIGN"], coll, s)
        box("signtrim_%s" % k, (ox, oy - 3.5, 9.6), (7.3, 0.34, 0.3),
            M["GOLD"], coll, s)
        box("signpost_%s" % k, (ox, oy - 3.4, 7.2), (1.3, 0.5, 1.5),
            M["DARK"], coll, s)

    elif t == "chunky":
        # few, fat, confident shapes - a toy you could injection-mould
        box("booth_roof_%s" % k, (ox, oy, 6.6), (9.8, 7.8, 1.2),
            M["BOOTH_TRIM"], coll, s)
        for i in range(5):
            mat = M["ROOF_A"] if i % 2 == 0 else M["ROOF_B"]
            box("awning_%s_%d" % (k, i), (ox - 3.84 + i * 1.92, oy - 4.2, 5.8),
                (1.92, 2.8, 0.5), mat, coll, s)
        box("sign_%s" % k, (ox, oy - 3.4, 8.3), (7.0, 0.7, 2.4), M["SIGN"], coll, s)
        box("signpost_%s" % k, (ox, oy - 3.4, 7.3), (1.2, 0.5, 1.4), M["DARK"], coll, s)

    elif t == "decorated":
        # fairground trim: bunting, window frame, planter, finials
        box("booth_roof_%s" % k, (ox, oy, 6.35), (9.4, 7.4, 0.7),
            M["BOOTH_TRIM"], coll, s)
        box("roof_lip_%s" % k, (ox, oy, 6.78), (9.8, 7.8, 0.18), M["DARK"], coll, s)
        for i in range(8):
            mat = M["ROOF_A"] if i % 2 == 0 else M["ROOF_B"]
            box("awning_%s_%d" % (k, i), (ox - 4.03 + i * 1.15, oy - 4.1, 5.85),
                (1.15, 2.6, 0.28), mat, coll, s)
        for side, dx in (("l", -2.75), ("r", 2.75)):
            box("winframe_%s_%s" % (k, side), (ox + dx, oy - 3.12, 4.9),
                (0.3, 0.5, 2.7), M["BOOTH_TRIM"], coll, s)
        box("winsill_%s" % k, (ox, oy - 3.12, 3.55), (6.0, 0.5, 0.28),
            M["BOOTH_TRIM"], coll, s)
        box("planter_%s" % k, (ox - 4.7, oy - 2.4, 0.7), (1.3, 1.3, 1.4),
            M["COUNTER"], coll, s)
        box("shrub_%s" % k, (ox - 4.7, oy - 2.4, 1.9), (1.5, 1.5, 1.1),
            M["GROUND"], coll, s)
        box("sign_%s" % k, (ox, oy - 3.4, 8.1), (6.6, 0.5, 2.1), M["SIGN"], coll, s)
        box("signtrim_%s" % k, (ox, oy - 3.5, 9.25), (6.9, 0.3, 0.25),
            M["GOLD"], coll, s)
        for side, dx in (("l", -2.7), ("r", 2.7)):
            box("signpost_%s_%s" % (k, side), (ox + dx, oy - 3.4, 7.15),
                (0.34, 0.34, 1.8), M["DARK"], coll, s)
            cyl("finial_%s_%s" % (k, side), (ox + dx, oy - 3.4, 9.45),
                0.22, 0.5, M["GOLD"], coll, s)

    else:  # panelled - semi-real kiosk with structural detail
        box("booth_roof_%s" % k, (ox, oy, 6.28), (9.2, 7.2, 0.55),
            M["BOOTH_TRIM"], coll, s)
        box("fascia_%s" % k, (ox, oy - 3.62, 6.05), (9.2, 0.22, 0.9),
            M["DARK"], coll, s)
        for i in range(10):
            mat = M["ROOF_A"] if i % 2 == 0 else M["ROOF_B"]
            box("awning_%s_%d" % (k, i), (ox - 4.14 + i * 0.92, oy - 4.05, 5.8),
                (0.92, 2.4, 0.2), mat, coll, s)
        # vertical panel seams down the body
        for i, dx in enumerate((-2.4, 0.0, 2.4)):
            box("seam_%s_%d" % (k, i), (ox + dx, oy + 3.02, 3.0),
                (0.14, 0.14, 5.6), M["DARK"], coll, s)
        for side, dx in (("l", -4.05), ("r", 4.05)):
            box("corner_%s_%s" % (k, side), (ox + dx, oy, 3.0),
                (0.2, 6.1, 6.0), M["DARK"], coll, s)
        cyl("pipe_%s" % k, (ox + 3.9, oy - 2.9, 3.0), 0.16, 6.0,
            M["RIDE_POLE"], coll, s)
        box("sign_%s" % k, (ox, oy - 3.4, 7.9), (6.2, 0.35, 1.7), M["SIGN"], coll, s)
        for side, dx in (("l", -2.5), ("r", 2.5)):
            cyl("signpost_%s_%s" % (k, side), (ox + dx, oy - 3.4, 7.1),
                0.12, 1.6, M["RIDE_POLE"], coll, s)

    for i, dx in enumerate((5.2, 6.8)):
        cyl("stile_%s_%d" % (k, i), (ox + dx, oy - 3.0, 1.6), 0.28, 3.2,
            M["RIDE_POLE"], coll, s)


def guest_colors(M, kind):
    skin = M["INFECT_SKIN"] if kind == "infected" else M["SKIN"]
    shirt = {
        "infected": M["INFECT_SHIRT"],
        "normal_a": M["SHIRT_A"],
        "normal_b": M["SHIRT_B"],
        "cult": M["SHIRT_A"],
    }[kind]
    return skin, shirt


def build_alien(style, M, ox, oy, coll):
    """Aliens in a coat. Double height - the tell is pure silhouette, so this
    is the part that proves whether a style can carry a shape-only read."""
    s = style
    tag = "%s_alien" % s["key"]
    d = s["detail"]
    w = s["torso"][0] * 1.10
    dep = s["torso"][1] * 1.35
    hd = s["head"]

    if d == "slab":
        box(tag + "_coat", (ox, oy, 4.9), (w, dep, 9.0), M["ALIEN_COAT"], coll, s)
        box(tag + "_head", (ox, oy, 10.0), (hd, dep, hd), M["SKIN"], coll, s)
        box(tag + "_hat", (ox, oy, 10.9), (hd * 1.7, dep, hd * 0.62), M["DARK"], coll, s)
        return

    box(tag + "_coat", (ox, oy, 4.7), (w, dep, 7.8), M["ALIEN_COAT"], coll, s)
    box(tag + "_leg_l", (ox - 0.6, oy, 0.42), (0.82, 0.86, 0.84), M["DARK"], coll, s)
    box(tag + "_leg_r", (ox + 0.6, oy, 0.42), (0.82, 0.86, 0.84), M["DARK"], coll, s)
    box(tag + "_collar", (ox, oy, 8.85), (w * 0.82, dep * 0.9, 0.6),
        M["ALIEN_COAT"], coll, s)
    box(tag + "_head", (ox, oy, 9.6 + hd * 0.2), (hd, hd, hd), M["SKIN"], coll, s)

    if d == "low":
        box(tag + "_hat", (ox, oy, 10.9), (hd * 1.5, hd * 1.5, hd * 0.7), M["DARK"], coll, s)
    else:
        box(tag + "_brim", (ox, oy, 10.5), (hd * 1.9, hd * 1.9, 0.22), M["DARK"], coll, s)
        box(tag + "_crown", (ox, oy, 11.0), (hd * 1.05, hd * 1.05, 0.85), M["DARK"], coll, s)
    if d == "high":
        box(tag + "_lapel", (ox, oy - dep * 0.45, 7.6), (w * 0.55, 0.12, 2.0),
            M["DARK"], coll, s)
        box(tag + "_belt", (ox, oy, 4.3), (w * 1.02, dep * 1.02, 0.4), M["DARK"], coll, s)


def build_guest(style, M, ox, oy, kind, coll):
    """A ~5-stud guest, assembled per the style's own form language."""
    s = style
    if kind == "alien":
        return build_alien(style, M, ox, oy, coll)

    tag = "%s_%s" % (s["key"], kind)
    skin, shirt = guest_colors(M, kind)
    d = s["detail"]
    tw, td, th = s["torso"]
    hd = s["head"]

    # ---- Paper style: three bold shapes, no limbs, card-thin -------------
    if d == "slab":
        lw, ld, lh = s["leg"]
        box(tag + "_legs", (ox, oy, lh / 2), (lw, ld, lh), M["PANTS"], coll, s)
        box(tag + "_notch", (ox, oy - ld * 0.1, lh / 2), (0.16, ld * 1.2, lh * 0.9),
            M["DARK"], coll, s)
        box(tag + "_torso", (ox, oy, lh + th / 2), (tw, td, th), shirt, coll, s)
        box(tag + "_head", (ox, oy, lh + th + hd / 2), (hd, td, hd), skin, coll, s)
        if kind == "cult":
            box(tag + "_amulet", (ox, oy - td * 0.6, lh + th * 0.55),
                (0.7, 0.12, 0.7), M["GOLD"], coll, s)
        return

    lw, ld, lh = s["leg"]
    aw, ad, ah = s["arm"]
    legs_h = lh * (2 if d == "high" else 1)          # thigh + shin when detailed
    arms_h = ah * (2 if d == "high" else 1)
    torso_z = legs_h + th / 2
    head_z = legs_h + th + hd / 2
    shoulder = legs_h + th

    # legs
    for sign, side in ((-1, "l"), (1, "r")):
        x = ox + sign * s["leg_gap"]
        if d == "high":
            box("%s_thigh_%s" % (tag, side), (x, oy, lh * 1.5),
                (lw, ld, lh), M["PANTS"], coll, s)
            box("%s_shin_%s" % (tag, side), (x, oy, lh * 0.5),
                (lw * 0.9, ld * 0.9, lh), M["PANTS"], coll, s)
            box("%s_shoe_%s" % (tag, side), (x, oy - ld * 0.15, 0.16),
                (lw * 1.05, ld * 1.5, 0.34), M["DARK"], coll, s)
        else:
            box("%s_leg_%s" % (tag, side), (x, oy, lh / 2),
                (lw, ld, lh), M["PANTS"], coll, s)
            if d == "mid":
                box("%s_shoe_%s" % (tag, side), (x, oy - ld * 0.12, 0.15),
                    (lw * 1.1, ld * 1.35, 0.3), M["DARK"], coll, s)

    box(tag + "_torso", (ox, oy, torso_z), (tw, td, th), shirt, coll, s)

    # arms
    for sign, side in ((-1, "l"), (1, "r")):
        x = ox + sign * s["arm_gap"]
        if d == "high":
            box("%s_uarm_%s" % (tag, side), (x, oy, shoulder - ah / 2),
                (aw, ad, ah), shirt, coll, s)
            box("%s_larm_%s" % (tag, side), (x, oy, shoulder - ah * 1.5),
                (aw * 0.92, ad * 0.92, ah), shirt, coll, s)
            box("%s_hand_%s" % (tag, side), (x, oy, shoulder - arms_h - 0.22),
                (aw * 1.05, ad * 1.05, 0.45), skin, coll, s)
        else:
            box("%s_arm_%s" % (tag, side), (x, oy, shoulder - ah / 2),
                (aw, ad, ah), shirt, coll, s)
            if d == "mid":
                box("%s_hand_%s" % (tag, side), (x, oy, shoulder - ah - 0.2),
                    (aw * 1.08, ad * 1.08, 0.4), skin, coll, s)

    if d == "high":
        box(tag + "_neck", (ox, oy, shoulder + 0.18), (hd * 0.55, hd * 0.55, 0.36),
            skin, coll, s)
        box(tag + "_belt", (ox, oy, legs_h + 0.16), (tw * 1.02, td * 1.02, 0.32),
            M["DARK"], coll, s)
    box(tag + "_head", (ox, oy, head_z), (hd, hd, hd), skin, coll, s)

    if d in ("mid", "high"):
        box(tag + "_hair", (ox, oy + hd * 0.06, head_z + hd * 0.42),
            (hd * 1.06, hd * 1.06, hd * 0.3), M["DARK"], coll, s)
        box(tag + "_collar", (ox, oy, shoulder - 0.12), (tw * 0.72, td * 1.06, 0.26),
            M["DARK"], coll, s)

    if kind == "cult":
        # shared amulet: a small accessory the player must spot ACROSS guests
        box(tag + "_cord", (ox, oy - td * 0.52, torso_z + th * 0.28),
            (0.85, 0.1, 0.42), M["DARK"], coll, s)
        box(tag + "_amulet", (ox, oy - td * 0.56, torso_z),
            (0.6, 0.18, 0.6), M["GOLD"], coll, s)
    if kind == "infected":
        # hand raised to the face - the cough loop, frozen
        box(tag + "_cough", (ox + tw * 0.5, oy - td * 0.55, head_z - hd * 0.3),
            (0.55, 0.55, 0.55), skin, coll, s)


def build_gate(style, M, oy, coll):
    build_booth(style, M, 0.0, oy, coll)
    for gx, kind in GUESTS:
        build_guest(style, M, gx, oy, kind, coll)


# --------------------------------------------------------------------------
# Probe 2 - palette / material board
# --------------------------------------------------------------------------

BOARD_ROWS = [
    ["BOOTH_BODY", "ROOF_A", "SIGN", "GROUND", "PATH", "DARK"],
    ["SKIN", "SHIRT_A", "SHIRT_B", "PANTS", "COUNTER", "GOLD"],
    ["INFECT_SKIN", "INFECT_SHIRT", "ALIEN_COAT", "RIDE_A", "RIDE_B", "RIDE_POLE"],
]


def build_board(style, M, oy, coll):
    ox = PROBE_PALETTE_X
    box("board_back", (ox, oy + 2.2, 6.0), (15.5, 0.6, 11.0), M["DARK"], coll, style)
    for r, row in enumerate(BOARD_ROWS):
        for c, slot in enumerate(row):
            x = ox - 6.0 + c * 2.4
            z = 9.6 - r * 2.9
            box("sw_%s_%d_%d" % (style["key"], r, c),
                (x, oy + 1.35, z), (2.0, 1.1, 2.0), M[slot], coll, style)
    # a neutral value strip so we can judge shading response, not just hue
    for i in range(6):
        g = 0.08 + i * 0.17
        h = "#%02X%02X%02X" % ((int(g * 255),) * 3)
        mat = SHADERS[style["shader"]]("%s_grey%d" % (style["key"], i), h, "GREY")
        box("grey_%s_%d" % (style["key"], i),
            (ox - 6.0 + i * 2.4, oy + 1.35, 1.6), (2.0, 1.1, 1.4), mat, coll, style)


# --------------------------------------------------------------------------
# Probe 3 - the day-1 carousel
# --------------------------------------------------------------------------

CAROUSEL_FORM = {
    # trim -> (canopy stripes, horse count, rim thickness, pole radius)
    "chunky":    (10, 6, 0.85, 0.30),
    "decorated": (16, 8, 0.50, 0.20),
    "billboard": (8,  6, 0.40, 0.26),
    "panelled":  (20, 8, 0.34, 0.15),
    "clw":       (12, 6, 0.70, 0.26),
}


def build_carousel(style, M, oy, coll):
    s = style
    k = s["key"]
    t = s["trim"]
    ox = PROBE_RIDE_X
    n_stripe, n_horse, rim_t, pole_r = CAROUSEL_FORM[t]

    if t == "billboard":
        cyl("ride_deck_%s" % k, (ox, oy, 0.5), 7.2, 1.0, M["PATH"], coll, s)
    else:
        cyl("ride_plinth_%s" % k, (ox, oy, 0.4), 7.6, 0.8, M["DARK"], coll, s)
        cyl("ride_deck_%s" % k, (ox, oy, 1.1), 7.0, 0.8, M["PATH"], coll, s)
    cyl("ride_column_%s" % k, (ox, oy, 6.8), 1.0, 11.4, M["RIDE_POLE"], coll, s)

    # canopy sits high and narrow so the horses stay visible from outside -
    # a carousel the player cannot see into is a carousel with no appeal
    for i in range(n_stripe):
        a0 = 2 * math.pi * i / n_stripe
        a1 = 2 * math.pi * (i + 1) / n_stripe
        mat = M["RIDE_A"] if i % 2 == 0 else M["RIDE_B"]
        wedge("canopy_%s_%d" % (k, i), (ox, oy, 13.4),
              7.7, 1.1, 3.6, a0, a1, mat, coll)

    cyl("canopy_rim_%s" % k, (ox, oy, 11.5), 7.8, rim_t, M["DARK"], coll, s)

    if t == "decorated":
        # bunting swags + a gold trim ring under the canopy
        cyl("trimring_%s" % k, (ox, oy, 11.15), 7.85, 0.22, M["GOLD"], coll, s)
        for i in range(16):
            a = 2 * math.pi * i / 16
            box("bunt_%s_%d" % (k, i),
                (ox + 7.6 * math.cos(a), oy + 7.6 * math.sin(a), 10.6),
                (0.55, 0.55, 0.7),
                M["RIDE_B"] if i % 2 else M["SIGN"], coll, s)
    elif t == "panelled":
        # structural tie-rods from column to canopy rim
        for i in range(8):
            a = 2 * math.pi * i / 8
            cyl("brace_%s_%d" % (k, i),
                (ox + 4.2 * math.cos(a), oy + 4.2 * math.sin(a), 11.0),
                0.08, 0.9, M["RIDE_POLE"], coll, s, n=8)
        cyl("hub_%s" % k, (ox, oy, 11.9), 1.5, 0.5, M["DARK"], coll, s)

    cyl("finial_%s" % k, (ox, oy, 16.0), 0.9, 1.7, M["GOLD"], coll, s,
        r_top=0.05, n=12)

    # alternating horse colours + a contrasting saddle, so a rank of horses
    # reads as horses rather than as a row of pale blobs
    horse_cycle = (M["HORSE"], M["SHIRT_B"], M["SHIRT_A"])
    # chunky horses are fatter and fewer; panelled ones are slimmer and denser
    fat = {"chunky": 1.22, "decorated": 1.0, "billboard": 0.85,
           "panelled": 0.82, "clw": 1.15}[t]
    for i in range(n_horse):
        a = 2 * math.pi * i / n_horse + math.pi / n_horse
        px, py = ox + 4.9 * math.cos(a), oy + 4.9 * math.sin(a)
        hide = horse_cycle[i % 3]
        yd = 1.0 * fat if t != "billboard" else 0.45
        cyl("pole_%s_%d" % (k, i), (px, py, 6.2), pole_r, 9.4,
            M["GOLD"], coll, s, n=10)
        box("horse_%s_%d" % (k, i), (px, py, 3.6),
            (2.4 * fat, yd, 1.5 * fat), hide, coll, s)
        box("hneck_%s_%d" % (k, i), (px + 1.0 * fat, py, 4.3),
            (0.7 * fat, yd * 0.72, 1.1), hide, coll, s)
        box("hhead_%s_%d" % (k, i), (px + 1.35 * fat, py, 4.9),
            (1.1 * fat, yd * 0.66, 0.7), hide, coll, s)
        box("hsaddle_%s_%d" % (k, i), (px - 0.15, py, 4.5),
            (1.1, yd * 1.05, 0.5), M["RIDE_A"], coll, s)
        box("htail_%s_%d" % (k, i), (px - 1.35 * fat, py, 4.1),
            (0.5, yd * 0.5, 1.0), M["GOLD"], coll, s)
        if t != "billboard":
            for j, dx in enumerate((-0.75, 0.7)):
                box("hleg_%s_%d_%d" % (k, i, j), (px + dx * fat, py, 2.6),
                    (0.5 * fat, yd * 0.85, 1.1), hide, coll, s)


# --------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------

def wipe():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    # unlink bay collections from the scene first, or they survive as empties
    # and pile up across re-runs
    for c in list(bpy.context.scene.collection.children):
        bpy.context.scene.collection.children.unlink(c)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                  bpy.data.cameras, bpy.data.lights, bpy.data.collections):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def look_at(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def build():
    wipe()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080

    for attr, val in (("taa_render_samples", 64), ("taa_samples", 16),
                      ("use_shadows", True), ("use_raytracing", True)):
        try:
            setattr(scene.eevee, attr, val)
        except Exception:
            pass

    # Cheerful world: bright blue sky doubling as fill light.
    world = bpy.data.worlds.new("ParkSky")
    scene.world = world
    world.use_nodes = True
    wnt = world.node_tree
    wnt.nodes.clear()
    wout = wnt.nodes.new("ShaderNodeOutputWorld")
    bg = wnt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = hexc("#8FC7F5")
    bg.inputs["Strength"].default_value = 0.85
    wnt.links.new(bg.outputs[0], wout.inputs[0])

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 4.2
    sun_data.color = (1.0, 0.96, 0.89)
    sun_data.angle = math.radians(3.0)      # soft-ish park shadows
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(52), 0, math.radians(38))
    scene.collection.objects.link(sun)

    text_mat = mat_toybox("label_ink", "#1B1D2A", "DARK")
    # neutral, style-agnostic backdrop so each bay is judged in isolation
    # and no neighbouring bay bleeds into its close-up
    backdrop_mat = mat_toybox("backdrop_neutral", "#AFB6C0", "BACKDROP")

    for i, style in enumerate(STYLES):
        oy = -i * ROW_PITCH
        coll = bpy.data.collections.new(style["label"])
        scene.collection.children.link(coll)
        M = build_palette(style)

        # each bay stands on its own ground so the ground material is compared too
        box("ground_%s" % style["key"], (32.0, oy + 1.0, -0.4),
            (132.0, 34.0, 0.8), M["GROUND"], coll)
        box("path_%s" % style["key"], (16.0, oy, 0.05),
            (56.0, 9.0, 0.3), M["PATH"], coll)
        # tall enough that no camera can see over it into the bay behind
        box("backdrop_%s" % style["key"], (32.0, oy + 17.2, 12.0),
            (132.0, 1.0, 24.0), backdrop_mat, coll)

        build_gate(style, M, oy, coll)
        build_board(style, M, oy, coll)
        build_carousel(style, M, oy, coll)

        # the locked style gets its depth baked in rather than shaded live
        if style.get("vao"):
            for ob in coll.objects:
                if ob.type == "MESH":
                    bake_vertex_ao(ob)

        label("row_%s" % style["key"], style["label"],
              (-32.0, oy - 13.5, 0.4), 2.4, text_mat, coll)

        # per-bay cameras: whole bay, tell close-up, palette, ride
        for suffix, lens, loc, tgt in (
            ("",       30, (19.0, oy - 46.0, 15.0), (19.0, oy, 5.0)),
            ("_TELL",  30, (20.0, oy - 30.0, 6.5),  (20.0, oy, 4.6)),
            ("_BOARD", 45, (PROBE_PALETTE_X, oy - 22.0, 6.0),
                           (PROBE_PALETTE_X, oy, 5.8)),
            ("_RIDE",  40, (PROBE_RIDE_X, oy - 27.0, 12.0),
                           (PROBE_RIDE_X, oy, 7.0)),
        ):
            name = "CAM_%s%s" % (style["key"], suffix)
            cd = bpy.data.cameras.new(name)
            cd.lens = lens
            c = bpy.data.objects.new(name, cd)
            c.location = loc
            scene.collection.objects.link(c)
            look_at(c, tgt)

    # column captions, once, well clear of the first bay
    # column captions share bay A's front lawn, clear of its row label
    for cx, cap in ((-2.0, "1  GATE + TELLS"),
                    (PROBE_PALETTE_X - 9.0, "2  PALETTE BOARD"),
                    (PROBE_RIDE_X - 7.0, "3  CAROUSEL")):
        label("cap_%s" % cap[0], cap, (cx, -13.5, 0.05), 2.4,
              text_mat, scene.collection)

    # Orthographic overview: every bay renders at identical scale, so the
    # comparison is not skewed by perspective falloff toward the back row.
    mid_y = -(len(STYLES) - 1) * ROW_PITCH / 2.0
    ov_data = bpy.data.cameras.new("CAM_OVERVIEW")
    ov_data.type = "ORTHO"
    ov_data.ortho_scale = 245.0
    ov = bpy.data.objects.new("CAM_OVERVIEW", ov_data)
    elev = math.radians(40.0)
    dist = 320.0
    ov.location = (32.0, mid_y - dist * math.cos(elev), dist * math.sin(elev))
    scene.collection.objects.link(ov)
    look_at(ov, (32.0, mid_y, 5.0))
    scene.camera = ov

    # a low, in-game-eye-level camera on bay A for the legibility read
    eye_data = bpy.data.cameras.new("CAM_PLAYER_EYE")
    eye_data.lens = 35
    eye = bpy.data.objects.new("CAM_PLAYER_EYE", eye_data)
    eye.location = (26.0, -17.0, 5.2)
    scene.collection.objects.link(eye)
    look_at(eye, (8.0, 0.0, 4.0))

    return scene


def set_viewport(cam_name="CAM_OVERVIEW", shading="RENDERED"):
    scene = bpy.context.scene
    cam = bpy.data.objects.get(cam_name)
    if cam:
        scene.camera = cam
    for area in bpy.context.screen.areas:
        if area.type != "VIEW_3D":
            continue
        for space in area.spaces:
            if space.type != "VIEW_3D":
                continue
            space.shading.type = shading
            space.overlay.show_overlays = False
            for region in area.regions:
                if region.type == "WINDOW":
                    region.data.view_perspective = "CAMERA"
        area.tag_redraw()


def save(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    return path


if __name__ == "__main__":
    build()
    set_viewport()
