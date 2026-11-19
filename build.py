from pathlib import Path
root=Path(__file__).resolve().parent
# Presentation fragments share the entry point's lexical state. Expand these
# explicit markers before compiling the one TI-Lua chunk; no runtime loading.
ui_views=(
    'beam_ui_single.lua',
    'beam_ui_continuous.lua',
    'beam_ui_portal.lua',
    'beam_ui_sections.lua',
)
parts=[]
for name, marker, localname in [
    ('section_db.lua','return DB\n','DB'),
    ('frame_core.lua','return Frame\n','Frame'),
    ('beam_preset.lua','return BeamPreset\n','BeamPreset'),
    ('continuous_preset.lua','return ContinuousPreset\n','ContinuousPreset'),
    ('portal_preset.lua','return PortalPreset\n','PortalPreset'),
    ('beam_ui.lua',None,None)]:
    src=(root/'src'/name).read_text(encoding='utf-8')
    if name=='beam_ui.lua':
        for view in ui_views:
            include='-- @include '+view
            assert src.count(include)==1, view
            src=src.replace(include,(root/'src'/view).read_text(encoding='utf-8').rstrip())
    if marker:
        assert src.rstrip().endswith(marker.strip()), name
        src=src[:src.rfind(marker)]
    # source-local tables are exposed to the concatenated UI by changing
    # their initial declaration from local to module-global (no require).
    if localname:
        src=src.replace('local '+localname+' =',localname+' =',1)
        if localname=='PortalPreset':
            src=src.replace('local PortalPreset=', 'PortalPreset=',1)
    parts.append(src)
out='-- BeamCX v0.6.1 (generated).\n'+'\n'.join(parts)
(root/'BeamCX.lua').write_text(out, encoding='utf-8')
print(f'Wrote BeamCX.lua: {len(out.encode()):,} bytes')
print('Package with: python3 tools/package.py')
