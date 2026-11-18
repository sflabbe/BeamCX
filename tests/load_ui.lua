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
        typing=typing}
end
]=]
    return assert((loadstring or load)(source..'\n'..snapshot,'@'..path))()
end
