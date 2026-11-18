from pathlib import Path
root=Path(__file__).resolve().parent
parts=[]
for name, marker, localname in [
    ('section_db.lua','return DB\n','DB'),
    ('frame_core.lua','return Frame\n','Frame'),
    ('beam_preset.lua','return BeamPreset\n','BeamPreset'),
    ('continuous_preset.lua','return ContinuousPreset\n','ContinuousPreset'),
    ('beam_ui.lua',None,None)]:
    src=(root/'src'/name).read_text(encoding='utf-8')
    if marker:
        assert src.rstrip().endswith(marker.strip()), name
        src=src[:src.rfind(marker)]
    # source-local tables are exposed to the concatenated UI by changing
    # their initial declaration from local to module-global (no require).
    if localname:
        src=src.replace('local '+localname+' =',localname+' =',1)
    parts.append(src)
out='-- BeamCX v0.5.0 (generated).\n'+'\n'.join(parts)
(root/'BeamCX.lua').write_text(out, encoding='utf-8')
print(f'Wrote BeamCX.lua: {len(out.encode()):,} bytes')
print('Package with: python3 tools/package.py')
