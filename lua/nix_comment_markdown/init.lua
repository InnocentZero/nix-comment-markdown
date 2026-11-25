local api, ts = vim.api, vim.treesitter
local rail = require("nix_comment_markdown.rail")
local adapter = require("nix_comment_markdown.markview")
local ns = api.nvim_create_namespace("nix-comment-markdown")
local stop = function() end
local empty = {}

local function is_nix(buf)
  return api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "nix" and vim.bo[buf].buftype == ""
end

local function cursor_row(buf)
  return buf == api.nvim_get_current_buf() and api.nvim_win_get_cursor(0)[1] - 1 or nil
end

local function project(buf, base, lines, prefixes, marks, rail_enabled)
  local last = #lines - 1
  for _, mark in ipairs(marks) do
    local anchor, col, style = unpack(mark)
    local row, finish = math.min(anchor, last), style.end_row or anchor
    -- Split ranges by source line so revealing one row doesn't drop a whole Markdown span.
    for r = row, math.min(finish, last) do
      local prefix, width = prefixes[r + 1], #lines[r + 1]
      local ending = r == finish and math.min(style.end_col or width, width) or width
      if r == row or ending > 0 then
        local opts, offset = vim.tbl_extend("force", {}, style), #prefix.raw
        opts.end_row, opts.end_col = nil, style.end_col and offset + ending
        if r ~= row then
          opts.virt_text, opts.virt_text_pos, opts.virt_text_hide = nil, nil, nil
          opts.virt_lines, opts.virt_lines_above = nil, nil
        elseif style.virt_lines then
          local chunks = rail.prefix(prefix, rail_enabled)
          opts.virt_lines = vim.tbl_map(function(line)
            return vim.list_extend({ unpack(chunks) }, line)
          end, style.virt_lines)
          opts.virt_lines_above = anchor <= last and style.virt_lines_above or false
        end
        local start = anchor > last and width or math.min(col, width)
        api.nvim_buf_set_extmark(buf, ns, base + r, offset + (r == row and start or 0), opts)
      end
    end
  end
end

local function refresh(buf, root, entry, config)
  local query = ts.query.parse("nix", "(comment) @comment")
  local cache, links = {}, config.images and {}
  local rail_opts = config.rail
  local base, next_row, lines, prefixes
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local function flush()
    if not lines then
      return
    end
    local key = table.concat(lines, "\n")
    local rendered = cache[key] or entry.cache[key] or { adapter.render(lines, links ~= nil) }
    cache[key] = rendered
    project(buf, base, lines, prefixes, rendered[1], rail_opts ~= nil)
    for row, path in pairs(rendered[2] or empty) do
      links[base + row] = { path = path, prefix = prefixes[row + 1] }
    end
  end
  for _, node in query:iter_captures(root, buf) do
    local row, col, last = node:range()
    local line = row == last and api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local start = line:match(config.pattern, col + 1)
    if start then
      local standalone = not line:sub(1, col):find("%S")
      if row ~= next_row or not standalone then
        flush()
        base, lines, prefixes = row, {}, {}
      end
      next_row = standalone and row + 1 or nil
      local finish = col + config.width
      lines[#lines + 1] = line:sub(start)
      prefixes[#prefixes + 1] = { marker_start = col, marker_end = finish, raw = line:sub(1, start - 1) }
      if rail_opts then
        rail_opts.end_col = finish
        api.nvim_buf_set_extmark(buf, ns, row, col, rail_opts)
      end
    end
  end
  flush()
  entry.tick, entry.cache, entry.links = api.nvim_buf_get_changedtick(buf), cache, links
  entry.raw_row, entry.hidden = nil, nil
end

local function reveal(buf, entry, row, images)
  local old = entry.raw_row
  if old == row then
    return
  end
  for _, mark in ipairs(entry.hidden or empty) do
    api.nvim_buf_set_extmark(buf, ns, old, mark[3], adapter.decoration(mark[4]))
  end
  entry.raw_row = row
  entry.hidden = row and api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
  if entry.hidden and #entry.hidden > 0 then
    api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
  end
  if images and (entry.links[old] or entry.links[row]) then
    images(buf, entry.links, row)
  end
end

local function setup(opts)
  opts = opts or {}
  local marker = opts.marker == nil and "|" or opts.marker
  assert(type(marker) == "string" and marker:match("^%S+$"), "marker must be nonempty and contain no whitespace")
  stop()
  local group = api.nvim_create_augroup("NixCommentMarkdown", { clear = true })
  local rail_opts = opts.rail ~= false and rail.setup(group) or nil
  local images = opts.images == true and require("nix_comment_markdown.images")(rail_opts ~= nil) or nil
  local config =
    { pattern = "^#" .. vim.pesc(marker) .. "[ \t]?()", width = #marker + 1, rail = rail_opts, images = images }
  local buffers = {}
  local function clear(buf, drop)
    local entry = buffers[buf]
    if not entry then
      return
    end
    buffers[buf] = not drop and { cache = entry.cache } or nil
    if entry.links then
      images(buf)
    end
    if entry.tick and api.nvim_buf_is_loaded(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
  local function on_event(event)
    local buf, name = event.buf, event.event
    local leaving = name == "BufLeave" or name == "WinLeave"
    local motion = leaving or name == "CursorMoved" or name == "CursorMovedI"
    local row = not leaving and cursor_row(buf) or nil
    if not motion then
      local drop = name == "BufUnload" or not is_nix(buf)
      if drop or row and not adapter.in_preview_mode() then
        return clear(buf, drop)
      end
    end
    local entry = buffers[buf]
    -- After an edit, refresh remaps all rows before we use their cached positions.
    local fresh = entry and entry.tick == api.nvim_buf_get_changedtick(buf)
    if fresh then
      reveal(buf, entry, row, motion and images)
    end
    if motion or fresh and not images or entry and entry.pending then
      return
    end
    entry = entry or { cache = empty }
    buffers[buf], entry.pending = entry, true
    vim.defer_fn(function()
      entry.pending = nil
      local row = cursor_row(buf)
      if buffers[buf] ~= entry or not is_nix(buf) or row and not adapter.in_preview_mode() then
        return
      end
      local parser = entry.tick ~= api.nvim_buf_get_changedtick(buf) and ts.get_parser(buf, "nix")
      if parser then
        refresh(buf, parser:parse()[1]:root(), entry, config)
        reveal(buf, entry, row)
      end
      if entry.links then
        images(buf, entry.links, entry.raw_row)
      end
    end, name:find("^TextChanged") and 80 or 0)
  end
  local events = "ModeChanged FileType BufEnter BufWinEnter WinEnter BufLeave WinLeave BufUnload"
    .. " TextChanged TextChangedI TextChangedP CursorMoved CursorMovedI"
  if images then
    events = events .. " TabEnter BufFilePost"
  end
  api.nvim_create_autocmd(vim.split(events, " "), { group = group, callback = on_event })
  for _, win in ipairs(api.nvim_list_wins()) do
    on_event({ buf = api.nvim_win_get_buf(win), event = "BufWinEnter" })
  end
  stop = function()
    for buf in pairs(buffers) do
      clear(buf, true)
    end
  end
end

return { setup = setup }
