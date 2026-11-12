#!/usr/bin/env python3
"""Pathwise preview: the addon's real Lua, drawn as web pages.

Runs Pathwise in Lua 5.1 (lupa) against the test client stub
(tests/stub.lua) plus tools/preview/render.lua, which lays frames out the
way the game does and measures text with the real Inter fonts. Each scene in
tools/preview/scenes.lua becomes preview/<scene>.html; tools/preview/shot.js
photographs them in Chromium.

    pip install lupa pillow
    python3 tools/preview/preview.py      (from the repository root)
    node tools/preview/shot.js

It is a picture of what Pathwise asks the game to draw, not the game: game
art (the real minimap, portraits, the world) is left out or stood in for.
"""

import base64
import html
import io
import json
import math
import os
import re
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageFont

ROOT = os.getcwd()
OUT = os.path.join(ROOT, "preview")
W, H = 1600, int(os.environ.get("PREVIEW_H") or 900)  # PREVIEW_H: a taller screen
FONT_DIR = os.path.join(ROOT, "Pathwise", "Media", "Fonts")
FONTS = {"regular": "Inter-Regular.ttf", "medium": "Inter-Medium.ttf", "semibold": "Inter-SemiBold.ttf"}


def line_height(size):
    return round(size * 1.25, 2)


def font_key(path):
    p = (path or "").lower()
    if "semibold" in p or "bold" in p:
        return "semibold"
    if "medium" in p:
        return "medium"
    return "regular"


_fonts = {}


def pil_font(path, size):
    key = (font_key(path), size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(FONT_DIR, FONTS[key[0]]), max(1, int(round(size))))
    return _fonts[key]


def wrap_lines(text, font, width):
    """Greedy word wrap, as the client wraps: by spaces, a long word alone."""
    out = []
    for para in text.split("\n"):
        if width is None:
            out.append(para)
            continue
        words = para.split(" ")
        line = ""
        for word in words:
            test = word if line == "" else line + " " + word
            if font.getlength(test) <= width + 0.5 or line == "":
                line = test
            else:
                out.append(line)
                line = word
        out.append(line)
    return out


def measure(text, path, size, width, wrap, max_lines):
    """Width and height of a text as the client would report them."""
    font = pil_font(path, size)
    lines = wrap_lines(text or "", font, width if (wrap and width) else None)
    if max_lines and max_lines > 0:
        lines = lines[: int(max_lines)]
    w = max((font.getlength(l) for l in lines), default=0)
    return w, len(lines) * line_height(size), len(lines)


# --- textures -------------------------------------------------------------

_png = {}


def texture_uri(path):
    if not isinstance(path, str):
        return None
    p = path.replace("\\", "/")
    m = re.match(r"(?i)interface/addons/(.+)$", p)
    if not m:
        return None  # game art: not ours to draw
    rel = m.group(1)
    if not os.path.splitext(rel)[1]:
        rel += ".tga"
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        return None
    if full not in _png:
        buf = io.BytesIO()
        Image.open(full).convert("RGBA").save(buf, "PNG")
        _png[full] = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
    return _png[full]


def rgba(c, alpha=1.0):
    """[r, g, b(, a)] in 0..1 as CSS, times `alpha`."""
    if not c:
        return f"rgba(255,255,255,{alpha:.3f})"
    a = (c[3] if len(c) > 3 and c[3] is not None else 1) * alpha
    return "rgba({},{},{},{:.3f})".format(*(int(round(max(0, min(1, c[i] or 0)) * 255)) for i in (0, 1, 2)), max(0, min(1, a)))


def lua_list(t):
    """A Lua array (1-based) as a Python list."""
    if t is None:
        return None
    return [t[i] for i in range(1, len(t) + 1)]


def colour_codes(text):
    """WoW's |cffRRGGBB ... |r as spans."""
    out, depth = [], 0
    i = 0
    s = text.replace("|n", "\n")
    while i < len(s):
        m = re.match(r"\|c([0-9a-fA-F]{2})([0-9a-fA-F]{6})", s[i:])
        if m:
            out.append(f'<span style="color:#{m.group(2)}">')
            depth += 1
            i += len(m.group(0))
            continue
        if s.startswith("|r", i):
            if depth:
                out.append("</span>")
                depth -= 1
            i += 2
            continue
        out.append(html.escape(s[i]))
        i += 1
    out.append("</span>" * depth)
    return "".join(out)


def font_faces():
    css = []
    for key, file in FONTS.items():
        with open(os.path.join(FONT_DIR, file), "rb") as f:
            data = base64.b64encode(f.read()).decode()
        css.append(f"@font-face{{font-family:pw-{key};src:url(data:font/ttf;base64,{data}) format('truetype');}}")
    return "\n".join(css)


JUSTIFY_V = {"TOP": "flex-start", "MIDDLE": "center", "BOTTOM": "flex-end"}
JUSTIFY_H = {"LEFT": "left", "CENTER": "center", "RIGHT": "right"}


def item_html(it, minimap):
    x, y, w, h = it["x"], it["y"], it["w"], it["h"]
    box = f"left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;"
    clip = lua_list(it.get("clip"))
    if clip:
        # Scrolled out of its scroll frame: cut to it, or left out.
        l, t, r, b = clip
        if x >= r or x + w <= l or y >= b or y + h <= t:
            return ""
        box += "clip-path:inset({:.2f}px {:.2f}px {:.2f}px {:.2f}px);".format(
            max(0, t - y), max(0, x + w - r), max(0, y + h - b), max(0, l - x))
    if it["kind"] == "Texture":
        alpha = it["alpha"]
        transform = []
        tc = lua_list(it.get("texCoord"))
        if tc and len(tc) == 4:
            sx = -1 if tc[0] > tc[1] else 1
            sy = -1 if tc[2] > tc[3] else 1
            if sx != 1 or sy != 1:
                transform.append(f"scale({sx},{sy})")
        rot = it.get("rotation")
        if rot:
            transform.append(f"rotate({-rot:.4f}rad)")
        style = box + (f"transform:{' '.join(transform)};" if transform else "")
        if it.get("blend") == "ADD":
            style += "mix-blend-mode:plus-lighter;"
        gr = lua_list(it.get("gradient"))
        if it.get("fill") == "color" and gr:
            # WoW: VERTICAL runs from the bottom colour up to the top one.
            c1, c2 = lua_list(gr[1]), lua_list(gr[2])
            direction = "to top" if gr[0] == "VERTICAL" else "to right"
            return f'<div class="t" style="{style}background:linear-gradient({direction},{rgba(c1, alpha)},{rgba(c2, alpha)})"></div>'
        if it.get("fill") == "color":
            c = lua_list(it.get("color"))
            col = rgba(c, alpha) if c else "transparent"
            return f'<div class="t" style="{style}background:{col}"></div>'
        uri = texture_uri(it.get("texture"))
        if not uri:
            return ""
        v = lua_list(it.get("vertex"))
        tint = rgba(v, alpha) if v else rgba(None, alpha)
        return (f'<div class="t" style="{style}background:{tint};'
                f'-webkit-mask-image:url({uri});mask-image:url({uri})"></div>')
    # Text.
    size = it["size"]
    c = lua_list(it.get("color"))
    color = rgba(c, it["alpha"]) if c else rgba(None, it["alpha"])
    style = box + (f"display:flex;align-items:{JUSTIFY_V.get(it['justifyV'], 'center')};"
                   f"font-family:pw-{font_key(it.get('font'))};font-size:{size}px;line-height:{line_height(size)}px;"
                   f"color:{color};")
    inner = f"width:100%;text-align:{JUSTIFY_H.get(it['justifyH'], 'center')};"
    if it.get("autoWidth") and "\n" not in it["text"]:
        inner += "white-space:pre;"
    elif it["wrap"]:
        inner += "white-space:pre-wrap;overflow-wrap:break-word;"
    else:
        inner += "white-space:pre;overflow:hidden;text-overflow:ellipsis;"
    if it.get("maxLines"):
        inner += f"display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:{int(it['maxLines'])};overflow:hidden;"
    if it.get("shadow"):
        inner += "text-shadow:1px -1px 0 rgba(0,0,0,.9),0 0 3px rgba(0,0,0,.6);"
    return f'<div class="x" style="{style}"><div style="{inner}">{colour_codes(it["text"])}</div></div>'


def page(items, title, minimap):
    body = []
    if minimap:
        mx, my, mw, mh = minimap
        body.append(f'<div class="minimap" style="left:{mx}px;top:{my}px;width:{mw}px;height:{mh}px"></div>')
    keyed = sorted(items, key=lambda it: (it["strata"], it["level"], it["layer"], it["sub"], it["order"]))
    body.extend(item_html(it, minimap) for it in keyed)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>
{font_faces()}
html,body{{margin:0;width:{W}px;height:{H}px;overflow:hidden}}
body{{position:relative;background:
 radial-gradient(1100px 480px at 60% 8%, #8fb7bf 0%, rgba(143,183,191,0) 70%),
 radial-gradient(900px 520px at 18% 100%, #3a5a33 0%, rgba(58,90,51,0) 72%),
 radial-gradient(700px 380px at 92% 92%, #2f4a35 0%, rgba(47,74,53,0) 70%),
 linear-gradient(180deg,#5d8791 0%,#3c6150 46%,#22382a 78%,#141f18 100%);}}
.t,.x,.minimap{{position:absolute;box-sizing:border-box}}
.t{{-webkit-mask-size:100% 100%;mask-size:100% 100%;-webkit-mask-repeat:no-repeat}}
.minimap{{border-radius:50%;background:radial-gradient(circle at 45% 40%,#6f8a5a,#3d5636 70%,#2a3b25);box-shadow:0 0 0 3px #1b1f24,0 0 0 5px #6b5a3a}}
.label{{position:absolute;left:18px;bottom:14px;font:12px/1.3 pw-regular,sans-serif;color:rgba(240,245,250,.75);text-shadow:0 1px 2px #000}}
</style></head>
<body>
{''.join(body)}
<div class="label">Pathwise v2 preview · {html.escape(title)} · drawn from the addon's Lua; the game world is a stand-in</div>
</body></html>
"""


def run_scene(name):
    """A scene by name; "hub@blossom" draws the hub in the Blossom theme."""
    name, _, theme = name.partition("@")
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.pymeasure = measure
    stub = rt.eval('function() return dofile("tests/stub.lua") end')()
    render = rt.eval('function(s) return assert(loadfile("tools/preview/render.lua"))(s) end')(stub)
    scenes = rt.eval('function(s, r) return assert(loadfile("tools/preview/scenes.lua"))(s, r) end')(stub, render)
    if theme:
        rt.execute('PathwiseSettings = { schema = 1, ui = { theme = "%s" } }' % theme)
    g.PATHWISE_PREVIEW = True  # no game art here: Pathwise's own drawings
    ns = stub.load(".")
    if scenes.addons is not None and scenes.addons[name] is not None:
        for addon in lua_list(scenes.addons[name]):
            stub.loadAddon(".", addon)
    scenes.setup()
    if scenes.before is not None and scenes.before[name] is not None:
        scenes.before[name]()
    stub.login()
    scenes.scenes[name](ns)
    items = []
    for it in lua_list(render.Dump()):
        items.append({k: it[k] for k in it})
    mm = None
    minimap = g.Minimap
    if minimap is not None:
        l, b, w, h = rt.eval('function(f) return f:GetRect() end')(minimap)
        if l is not None:
            mm = (l, H - b - h, w, h)
    errors = [p for p in lua_list(stub.printed) if "error" in p]
    return items, mm, errors


# The other Pathwise addons (Pathwise UI and the kit's Heal, Encounters,
# Loot), on their own test client (tests/ui/stub.lua): addon, what opens.
KIT_SCENES = {
    "ui-options": ("PathwiseUI", 'SlashCmdList.PATHWISEUI("")'),
    "loot-browser": ("Pathwise_Loot", "ns.LootBrowser.Show()"),
    "loot-options": ("Pathwise_Loot", 'SlashCmdList.PATHWISELOOT("options")'),
    "heal-options": ("Pathwise_Heal", 'SlashCmdList.PATHWISEHEAL("")'),
    "encounters-options": ("Pathwise_Encounters", 'SlashCmdList.PATHWISEENCOUNTERS("")'),
}


def run_kit(name, theme):
    addon, opener = KIT_SCENES[name]
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.pymeasure = measure
    g.PATHWISE_PREVIEW = True
    stub = rt.eval('function() return dofile("tests/ui/stub.lua") end')()
    render = rt.eval('function(s) return assert(loadfile("tools/preview/render.lua"))(s) end')(stub)
    ns = stub.loadAddon(".", addon)
    # The theme chosen before login, as after a reload with it saved.
    if theme and ns.Theme is not None and ns.Theme.UseScheme is not None:
        ns.Theme.UseScheme(theme)
    stub.login(addon)
    rt.eval("function(ns) " + opener + " end")(ns)
    stub.advance(1)  # windows fade in
    items = [{k: it[k] for k in it} for it in lua_list(render.Dump())]
    errors = [p for p in lua_list(stub.printed) if "error" in p]
    return items, None, errors


def main():
    os.makedirs(OUT, exist_ok=True)
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    order = rt.eval('function() return assert(loadfile("tools/preview/scenes.lua"))({}, {}) end')()
    names = sys.argv[1:] or lua_list(order.order)
    if names and names[0] == "themes":
        # Every theme: preview/<scene>@<theme>.html for each scene named
        # after "themes" (the hub when none is).
        keys = rt.eval('function() local t = {} local f = assert(io.open("Pathwise/Theme/Signature.lua")):read("*a") for k in f:gmatch(\'{ key = "([%w]+)"\') do t[#t + 1] = k end return t end')()
        wanted = names[1:] or ["hub"]
        names = [f"{sc}@{k}" for sc in wanted for k in lua_list(keys)]
    for name in names:
        base, _, theme = name.partition("@")
        if base in KIT_SCENES:
            items, mm, errors = run_kit(base, theme or None)
        else:
            items, mm, errors = run_scene(name)
        with open(os.path.join(OUT, f"{name}.html"), "w") as f:
            f.write(page(items, name, mm))
        print(f"preview/{name}.html: {len(items)} regions" + (f"  ({len(errors)} errors: {errors[:2]})" if errors else ""))


if __name__ == "__main__":
    main()
