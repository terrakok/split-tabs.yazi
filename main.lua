--- @since 26.5.6
--- @sync entry

-- nil when inactive; holds all dual-pane state when active.
local dp = nil
local saved = {}

local function active_pane()
    return cx.tabs.idx == dp.tabs[2] and 2 or 1
end

local function other_pane()
    return active_pane() == 1 and 2 or 1
end

-- Minimal component: renders static elements. Needs _id/_area for ui.redraw().
local Overlay = {}
function Overlay:new(id, area, elements)
    return setmetatable({ _id = id, _area = area, _elements = elements or {} }, { __index = self })
end

function Overlay:reflow() return {} end

function Overlay:redraw() return self._elements end

-- Polyfill: Marker lacks reflow(), which crashes Tab:reflow() on resize.
if not Marker.reflow then
    Marker.reflow = function() return {} end
end

-- Wraps a Current to suppress cursor highlight via dp._no_cursor flag.
local Pane = {}
function Pane:new(area, tab, active)
    return setmetatable(
        { _id = active and "current" or "my-current", _area = area, _active = active, _inner = Current:new(area, tab) },
        { __index = self }
    )
end

function Pane:reflow() return self._inner:reflow() end

function Pane:redraw()
    dp._no_cursor = not self._active
    local elements = self._inner:redraw()
    dp._no_cursor = nil
    return elements
end

local function apply_dual_tab_patch()
    Tab.layout = function(self)
        if #cx.tabs < 2 and not dp.creating then
            dp.creating = true
            ya.emit("tab_create", { cx.active.current.cwd })
            dp.tabs = { 1, 2 }
        elseif #cx.tabs >= 2 then
            dp.creating = nil
        end

        if #cx.tabs > 2 then
            for i = #cx.tabs, 1, -1 do
                if i ~= dp.tabs[1] and i ~= dp.tabs[2] then
                    ya.emit("tab_close", { i - 1 }) -- 0-based
                    break
                end
            end
        end

        dp.pane = active_pane()

        -- Preview on: split vertically first, then horizontally for panes.
        local pane_area = self._area
        if dp.preview then
            local vsplit = ui.Layout()
                :direction(ui.Layout.VERTICAL)
                :constraints({
                    ui.Constraint.Fill(1),
                    ui.Constraint.Fill(1),
                })
                :split(self._area)
            pane_area = vsplit[1]
            dp.preview_area = vsplit[2]
        else
            dp.preview_area = nil
        end

        -- Active pane uses the "current" slot; inactive gets a zero-width slot.
        self._chunks = ui.Layout()
            :direction(ui.Layout.HORIZONTAL)
            :constraints({
                ui.Constraint.Fill(1),
                ui.Constraint.Fill(1),
                ui.Constraint.Length(0),
            })
            :split(pane_area)
    end

    Tab.build = function(self, ...)
        saved.tab_build(self, ...)

        local c = self._chunks
        local tab1 = cx.tabs[dp.tabs[1]]
        local tab2 = cx.tabs[dp.tabs[2]]

        if not tab1 or not tab2 then
            self._children = {}
            return
        end

        self._children = {
            Pane:new(c[1]:pad(ui.Pad(0, 0, 0, 1)), tab1, dp.pane == 1),
            Pane:new(c[2]:pad(ui.Pad.x(1)), tab2, dp.pane == 2),

            Marker:new(c[1], tab1.current),

            Rails:new(c, self._tab), -- draw a rail between "parent" and "current" panels
            Marker:new(c[2], tab2.current),
        }

        if dp.preview and dp.preview_area then
            -- Overlap preview 1 row up to share the pane's bottom border line.
            local pa = dp.preview_area
            local joined = ui.Rect { x = pa.x, y = pa.y - 1, w = pa.w, h = pa.h + 1 }
            self._children[#self._children + 1] = Overlay:new("border", joined, {
                ui.Border(ui.Edge.ALL):area(joined),
            })
            self._children[#self._children + 1] = Preview:new(joined:pad(ui.Pad(1, 1, 1, 1)), self._tab)
        else
            -- Zero-width "preview" rect prevents stale Rust-side preview rendering.
            -- Height stays non-zero so Folder::make window size isn't clamped to 0.
            self._children[#self._children + 1] = Overlay:new("preview",
                ui.Rect { x = 0, y = 0, w = 0, h = self._area.h }, {})
        end
    end
end

local function apply_header_patch()
    Header.cwd = function(self)
        local w = self._area.w
        local mid = math.floor(w / 2) - 1

        local tab1 = cx.tabs[dp.tabs[1]]
        local tab2 = dp.tabs[2] and cx.tabs[dp.tabs[2]]
        local pane = dp.pane or 1

        if not tab1 then return "" end

        if not tab2 then
            local s = ya.readable_path(tostring(tab1.current.cwd))
            return ui.Span(ui.truncate(s, { max = w, rtl = true })):style(th.tabs.active)
        end

        -- Left path: pad to exactly `mid` columns so the separator aligns with the pane split.
        local p1 = ya.readable_path(tostring(tab1.current.cwd))
        p1 = ui.truncate(p1, { max = mid, rtl = true })
        local pad = mid - #p1
        if pad > 0 then
            p1 = p1 .. string.rep(" ", pad)
        end

        local right_avail = math.max(0, w - mid - 1 - (self._right_width or 0)) - 4
        local p2 = ya.readable_path(tostring(tab2.current.cwd))
        p2 = ui.truncate(p2, { max = right_avail, rtl = true })

        local s_active = th.tabs.active:patch(ui.Style():bg("reset"))
        local s_inactive = th.tabs.inactive:patch(ui.Style():bg("reset"))

        return ui.Line {
            ui.Span(p1):style(pane == 1 and s_active or s_inactive),
            ui.Span(" "),
            ui.Span(p2):style(pane == 2 and s_active or s_inactive),
        }
    end
end

local function restore_all()
    Tab.layout = saved.tab_layout
    Tab.build = saved.tab_build
    Header.cwd = saved.header_cwd
    Tabs.height = saved.tabs_height
    Entity.style = saved.entity_style
end

local function activate()
    if dp then return end

    ps.sub("ind-watch", function(args)
        args.files = { cx.tabs[dp.tabs[1]].current.file, cx.tabs[dp.tabs[2]].current.file }

        -- If the preview pane is active and the hovered entity is a directory,
        -- add it to the watch list as well so that the directory can be loaded when absent.
        local hovered = cx.tabs[active_pane()].current.hovered
        if dp.preview and hovered and hovered.cha.is_dir then
                args.files[#args.files + 1] = hovered
        end

        return args
    end)

    ps.sub("relay-update-files", function(args)
        args.tabs = { cx.tabs[dp.tabs[1]].id, cx.tabs[dp.tabs[2]].id }
        return args
    end)

    saved.tab_layout = Tab.layout
    saved.tab_build = Tab.build
    saved.header_cwd = Header.cwd
    saved.tabs_height = Tabs.height
    saved.entity_style = Entity.style

    Entity.style = function(self)
        if dp and dp._no_cursor then
            return self._file:style() or ui.Style()
        end
        return saved.entity_style(self)
    end

    Tabs.height = function() return 0 end

    local n = #cx.tabs
    local cur = cx.tabs.idx
    local tab2_idx

    if n >= 2 then
        tab2_idx = (cur < n) and (cur + 1) or 1
    else
        tab2_idx = 2
        ya.emit("tab_create", { cx.active.current.cwd })
    end

    dp = { pane = 1, view = "dual", tabs = { cur, tab2_idx }, creating = n < 2, preview = false }

    apply_dual_tab_patch()
    apply_header_patch()
    ui.render()
end

local function deactivate()
    if not dp then return end
    ps.unsub("ind-watch")
    ps.unsub("relay-update-files")
    ya.emit("tab_close", { other_pane() - 1 })
    restore_all()
    dp = nil
    saved = {}
    ui.render()
end

local function spl_toggle()
    if dp then deactivate() else activate() end
end

local function spl_preview()
    if not dp then return end
    dp.preview = not dp.preview
    ui.render()
    if dp.preview then
        ya.emit("peek", { 0 })
    else
        -- Different skip value forces preview.reset() which clears protocol images.
        ya.emit("peek", { 99999 })
    end
end

local function spl_switch_tab()
    if not dp then return end
    ya.emit("tab_switch", { dp.tabs[other_pane()] - 1 })
    ui.render()
end

local function entry(st, job)
    job = type(job) == "string" and { args = { job } } or job
    local act = job.args[1]

    if act == "spl_toggle" then
        spl_toggle()
    elseif act == "spl_switch_tab" then
        spl_switch_tab()
    elseif act == "spl_preview" then
        spl_preview()
    end
end

return { entry = entry }
