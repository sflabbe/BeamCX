"""Render captured P6B/current commands side by side at all three canvas sizes."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('commands', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()


def render(path):
    frames = []
    color, font = 'white', None
    for line in path.read_text().splitlines():
        kind, *v = json.loads(line)
        if kind not in {'font', 'color', 'pen', 'text', 'rect', 'line', 'polygon'}:
            width, height = v
            frame = Image.new('RGB', (width, height))
            draw = ImageDraw.Draw(frame)
            frames.append(((width, height, kind), frame))
        elif kind == 'font':
            face, style, size = v
            suffix = '-Bold' if style == 'b' else ''
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono'+suffix+'.ttf', size)
        elif kind == 'color':
            color = tuple(v)
        elif kind == 'rect':
            x, y, w, h = v
            draw.rectangle((x, y, x+w, y+h), fill=color)
        elif kind == 'line':
            draw.line(v, fill=color)
        elif kind == 'polygon':
            draw.polygon(list(zip(v[::2], v[1::2])), fill=color)
        elif kind == 'text':
            text, x, y, *_ = v
            draw.text((x, y), text, font=font, fill=color, anchor='lt')
    return frames


before, after = render(args.commands/'before.jsonl'), render(args.commands/'after.jsonl')
assert len(before) == len(after)
groups = {}
for (key, a), (other, b) in zip(before, after):
    assert key == other
    assert a.tobytes() == b.tobytes(), key
    groups.setdefault(key[:2], []).append((key[2], a, b))
rows = max(map(len, groups.values()))
cell_w, cell_h, padding = 336, 280, 16
sheet = Image.new('RGB', (6*cell_w+padding, rows*cell_h+80), '#e5ebf1')
draw = ImageDraw.Draw(sheet)
heading = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 14)
draw.text((padding, 8), 'P6C-0 | exact P6B / extracted UI | PC simulation; physical CX acceptance pending', font=heading, fill='#122c42')
for column, (size, frames) in enumerate(groups.items()):
    for side, label in enumerate(('P6B before', 'P6C-0 after')):
        x = padding+(column*2+side)*cell_w
        draw.text((x, 37), f'{size[0]} x {size[1]} | {label}', font=heading, fill='#122c42')
        for row, (title, a, b) in enumerate(frames):
            y = 80+row*cell_h
            draw.text((x, y), title, font=heading, fill='#122c42')
            sheet.paste((a, b)[side], (x, y+24))
sheet.save(args.output)
print(f'PASS: {len(before)} byte-identical before/after rasters; wrote {args.output}')
