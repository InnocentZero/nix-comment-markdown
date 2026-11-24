local api, ts = vim.api, vim.treesitter
local rail = require("nix_comment_markdown.rail")
local adapter = require("nix_comment_markdown.markview")
local ns = api.nvim_create_namespace("nix-comment-markdown")
local stop
local empty = {}

local function state(buf, event)
  if
    event == "BufUnload"
    or not api.nvim_buf_is_loaded(buf)
    or vim.bo[buf].filetype ~= "nix"
    or vim.bo[buf].buftype ~= ""
  then
    return "detach"
  end
  return (buf ~= api.nvim_get_current_buf() or adapter.in_preview_mode()) and "preview" or "raw"
end

local function project(buf, base, lines, prefixes, marks, rail_enabled)
  local function position(row, col)
    if row >= #lines then
      row, col = #lines - 1, #lines[#lines]
    end
    return base + row, #prefixes[row + 1].raw + math.min(col, #lines[row + 1])
  end
  for _, mark in ipairs(marks) do
    local _, row, col, details = unpack(mark)
    local opts = mark.options
    if details.virt_lines then
      local chunks = rail.prefix(prefixes[math.min(row + 1, #lines)], rail_enabled)
      opts.virt_lines = vim.tbl_map(function(line)
        return vim.list_extend({ unpack(chunks) }, line)
      end, details.virt_lines)
      opts.virt_lines_above = row < #lines and details.virt_lines_above or false
    end
    if details.end_row then
      opts.end_row, opts.end_col = position(details.end_row, details.end_col)
    end
    local r, c = position(row, col)
    api.nvim_buf_set_extmark(buf, ns, r, c, opts)
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
end

local function session(config)
  local buffers, images = {}, config.images
  local function clear(buf, drop)
    local entry = buffers[buf]
    if not entry then
      return
    end
    buffers[buf] = not drop and { cache = entry.cache } or nil
    if not (drop or entry.tick) then
      return
    end
    if images then
      images(buf)
    end
    if api.nvim_buf_is_loaded(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
  local function on_event(event)
    local buf = event.buf
    local mode = state(buf, event.event)
    if mode ~= "preview" then
      return clear(buf, mode == "detach")
    end
    local entry = buffers[buf] or { cache = empty }
    if entry.pending or not images and entry.tick == api.nvim_buf_get_changedtick(buf) then
      return
    end
    buffers[buf], entry.pending = entry, true
    vim.defer_fn(function()
      entry.pending = nil
      if buffers[buf] ~= entry or state(buf) ~= "preview" then
        return
      end
      local parser = entry.tick ~= api.nvim_buf_get_changedtick(buf) and ts.get_parser(buf, "nix")
      if parser then
        refresh(buf, parser:parse()[1]:root(), entry, config)
      end
      if entry.links then
        images(buf, entry.links)
      end
    end, event.event:find("^TextChanged") and 80 or 0)
  end
  return on_event, function()
    for buf in pairs(buffers) do
      clear(buf, true)
    end
  end
end

local function setup(opts)
  opts = opts or {}
  local marker = opts.marker == nil and "|" or opts.marker
  assert(type(marker) == "string" and marker:match("^%S+$"), "marker must be nonempty and contain no whitespace")
  if stop then
    stop()
  end
  local group = api.nvim_create_augroup("NixCommentMarkdown", { clear = true })
  local rail_opts = opts.rail ~= false and rail.setup(group) or nil
  local images = opts.images == true and require("nix_comment_markdown.images")(rail_opts ~= nil) or nil
  local on_event
  on_event, stop = session({
    pattern = "^#" .. vim.pesc(marker) .. "[ \t]?()",
    width = #marker + 1,
    rail = rail_opts,
    images = images,
  })
  local events = "ModeChanged FileType BufEnter BufWinEnter TextChanged TextChangedI TextChangedP BufUnload"
  if images then
    events = events .. " WinEnter TabEnter BufFilePost"
  end
  api.nvim_create_autocmd(vim.split(events, " "), { group = group, callback = on_event })
  for _, win in ipairs(api.nvim_list_wins()) do
    on_event({ buf = api.nvim_win_get_buf(win), event = "BufWinEnter" })
  end
end

return { setup = setup }
