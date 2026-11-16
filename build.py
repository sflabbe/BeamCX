from pathlib import Path
root=Path(__file__).resolve().parent
parts=[]
for name, marker, localname in [
    ('section_db.lua','return DB\n','DB'),
    ('beam_core.lua','return Beam\n','Beam'),
    ('beam_ui.lua',None,None)]:
    src=(root/'src'/name).read_text(encoding='utf-8')
    if marker:
        assert src.rstrip().endswith(marker.strip()), name
        src=src[:src.rfind(marker)]
    # source-local tables are exposed to the concatenated UI by changing
    # their initial declaration from local to module-global (no require).
    if localname:
        src=src.replace('local '+localname+' = {}',localname+' = {}',1)
    parts.append(src)
out='-- BeamCX v0.2.3 (generated).\n'+'\n'.join(parts)
(root/'BeamCX.lua').write_text(out, encoding='utf-8')
print(f'Wrote BeamCX.lua: {len(out.encode()):,} bytes')
print('Convert to .tns with: ~/Luna/luna BeamCX.lua BeamCX.tns')
