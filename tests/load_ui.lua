-- Test-only snapshot appended to the bundle in the same lexical chunk.
return function(path)
    local file=assert(io.open(path,'r'))
    local source=file:read('*a');file:close()
    local snapshot=[=[
-- Read-only test snapshot. Result / summary references allow rollback identity
-- checks; this accessor does not modify app state and is not part of the UI.
function _BX_TEST_STATE()
    return {page=page,sel_index=sel_index,selector_error=selector_error,
        support=params.support,EI=params.EI,result=result,summary=summary,err=err,
        export_message=export_message,q_sw=q_sw,self_weight=settings.self_weight,
        typing=typing,restore_notice=restore_notice,format_number=fmt,
        continuous=copy(continuous),samples=samples,cursor_value=cursor_value,
        stale=stale,calculating=calculating,table_page=table_page,edit_index=edit_index,
        edit_top=edit_top,characteristic=characteristic,
        portal=copy(portal),portal_member=portal_member,portal_s=portal_s,portal_side=portal_side,
        portal_sections=copy(portal_sections),portal_section_group=portal_section_group,
        portal_beam_self_weight=portal_beam_self_weight,sec_index=sec_index,sec_top=sec_top,
        section_rows=section_rows}
end
]=]
    return assert((loadstring or load)(source..'\n'..snapshot,'@'..path))()
end
