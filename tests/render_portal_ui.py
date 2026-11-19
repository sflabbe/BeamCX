"""Render actual bundled TI-Lua commands; simulation, not calculator pixels.

Run: python3 tests/render_portal_ui.py (Lua 5.1 and existing Pillow required).
The recorder and layout assertions are shared with the portal UI suite.
"""
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
script = f"local root={str(root)!r}\n" + (root/'tests/portal_contact.lua').read_text()
result = subprocess.run(['lua5.1', '-'], input=script, text=True, capture_output=True, cwd=root, check=True)
scale = 3
screens = []
color = (255, 255, 255)
font = None
for line in result.stdout.splitlines():
    kind, *values = json.loads(line)
    if kind == 'screen':
        title = values[0]
        frame = Image.new('RGB', (318*scale, 212*scale))
        draw = ImageDraw.Draw(frame)
        screens.append((title, frame))
    elif kind == 'color':
        color = tuple(values)
    elif kind == 'font':
        style, size = values
        path = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono' + ('-Bold' if style == 'b' else '') + '.ttf'
        font = ImageFont.truetype(path, size*scale)
    elif kind == 'rect':
        x, y, w, h = values
        draw.rectangle((x*scale, y*scale, (x+w)*scale, (y+h)*scale), fill=color)
    elif kind == 'line':
        draw.line(tuple(v*scale for v in values), fill=color, width=scale)
    elif kind == 'polygon':
        draw.polygon([(values[i]*scale, values[i+1]*scale) for i in range(0, len(values), 2)], fill=color)
    elif kind == 'text':
        text, x, y = values
        draw.text((x*scale, y*scale), text, fill=color, font=font, anchor='lt')

columns = 2
padding, title_height = 24, 38
cell_w, cell_h = 318*scale+padding, 212*scale+title_height+padding
sheet = Image.new('RGB', (columns*cell_w+padding, ((len(screens)+columns-1)//columns)*cell_h+100), '#e5ebf1')
draw = ImageDraw.Draw(sheet)
heading = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
draw.text((padding, 12), 'BeamCX v0.6.1 | real application drawing commands | PC simulation', fill='#122c42', font=heading)
draw.text((padding, 43), '318 x 212 simulated canvas; font metrics differ from physical TI-Nspire CX CAS.', fill='#385169', font=heading)
for index, (title, frame) in enumerate(screens):
    x = padding+(index % columns)*cell_w
    y = 100+(index//columns)*cell_h
    draw.text((x, y), title, fill='#122c42', font=heading)
    sheet.paste(frame, (x, y+title_height))
output = root/'PORTAL_UI_CONTACT.png'
sheet.save(output)
print(f'Wrote {output}: {len(screens)} real application screens')
