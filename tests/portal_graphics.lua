-- Test-only graphics recorder. All output comes from the bundled on.paint.
return function(width,height)
    local gc={size=10,commands={},texts={},lines={},polygons={},rgb={}}
    local function command(kind,...) gc.commands[#gc.commands+1]={kind,...} end
    local function point(x,y)
        assert(x>=-1e-8 and y>=-1e-8 and x<=width()+1e-8 and y<=height()+1e-8,
            'outside canvas '..x..','..y)
    end
    function gc:reset() self.commands={};self.texts={};self.lines={};self.polygons={} end
    function gc:setColorRGB(r,g,b) self.rgb={r,g,b};command('color',r,g,b) end
    function gc:setFont(face,style,size) self.size=size;command('font',style,size) end
    function gc:getStringWidth(t) return #t:gsub('[\128-\191]','')*self.size*.7 end
    function gc:getStringHeight() return self.size+3 end
    function gc:setPen(pen,style) command('pen',pen,style) end
    function gc:fillRect(x,y,w,h) point(x,y);point(x+w,y+h);command('rect',x,y,w,h) end
    function gc:drawLine(x,y,xx,yy)
        point(x,y);point(xx,yy)
        self.lines[#self.lines+1]={x,y,xx,yy,color=self.rgb}
        command('line',x,y,xx,yy)
    end
    function gc:fillPolygon(p)
        for i=1,#p,2 do point(p[i],p[i+1]) end
        self.polygons[#self.polygons+1]={points=p,color=self.rgb}
        command('polygon',(table.unpack or unpack)(p))
    end
    function gc:drawString(t,x,y)
        local w,h=self:getStringWidth(t),self:getStringHeight()
        point(x,y);point(x+w,y+h)
        for _,b in ipairs(self.texts) do
            assert(x+w<=b.x+.001 or b.x+b.w<=x+.001 or y+h<=b.y+.001 or b.y+b.h<=y+.001,
                'overlap: '..t..' / '..b.t)
        end
        self.texts[#self.texts+1]={t=t,x=x,y=y,w=w,h=h}
        command('text',t,x,y)
    end
    return gc
end
