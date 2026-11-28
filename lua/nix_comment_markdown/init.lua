local api = vim.api
local blocks = require("nix_comment_markdown.blocks")
local markview = require("nix_comment_markdown.markview")
local rail = require("nix_comment_markdown.rail")
local ns = api.nvim_create_namespace("nix-comment-markdown")
local buffers, config = {}, nil

local function is_nix(buf)
  return api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "nix" and vim.bo[buf].buftype == ""
end

local function cursor_row(buf)
  return buf == api.nvim_get_current_buf() and api.nvim_win_get_cursor(0)[1] - 1 or nil
end

local function previewing(buf)
  return not cursor_row(buf) or require("markview.actions").in_preview_mode()
end

local function window_width(buf)
  local win = buf == api.nvim_get_current_buf() and api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  local info = vim.fn.getwininfo(win)[1]
  return info and info.width - info.textoff or vim.o.columns
end

local function version(buf)
  return api.nvim_buf_get_changedtick(buf) .. ":" .. window_width(buf)
end

local function warn(err)
  vim.notify_once("nix-comment-markdown: " .. tostring(err), vim.log.levels.WARN)
end

local function refresh(buf, entry)
  local found, err = blocks.find(buf, config.pattern)
  if not found then
    return warn(err)
  end
  local width, cache, links = window_width(buf), {}, config.images and {} or nil
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, block in ipairs(found) do
    local text = vim.tbl_map(function(line)
      return line.text
    end, block.lines)
    local fit = math.max(1, width - rail.width(block.lines[1], config.rail))
    local key = fit .. "\n" .. table.concat(text, "\n")
    local ok, marks, images = true, unpack(cache[key] or entry.cache[key] or {})
    if not marks then
      ok, marks, images = pcall(markview.render, text, fit, links ~= nil)
    end
    if ok then
      cache[key] = { marks, images }
      blocks.place(buf, ns, block, marks, config.rail)
      for row, path in pairs(images or {}) do
        links[block.row + row] = { path = path, line = block.lines[row + 1] }
      end
    else
      warn(marks)
    end
  end
  entry.cache, entry.links, entry.version, entry.raw_row, entry.hidden = cache, links, version(buf), nil, nil
end

local function reveal(buf, entry, row)
  local old = entry.raw_row
  if old == row then
    return
  end
  for _, mark in ipairs(entry.hidden or {}) do
    api.nvim_buf_set_extmark(buf, ns, old, mark[3], blocks.options(mark[4]))
  end
  entry.raw_row = row
  entry.hidden = row and api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true }) or nil
  for _, mark in ipairs(entry.hidden or {}) do
    api.nvim_buf_del_extmark(buf, ns, mark[1])
  end
  if entry.links and (entry.links[old] or entry.links[row]) then
    config.images.sync(buf, entry.links, row)
  end
end

local function schedule(buf, entry, delay)
  if entry.pending then
    return
  end
  entry.pending = true
  vim.defer_fn(function()
    entry.pending = nil
    if buffers[buf] ~= entry or not is_nix(buf) or not previewing(buf) then
      return
    end
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win][0].conceallevel = 2
    end
    if entry.version ~= version(buf) then
      refresh(buf, entry)
    end
    reveal(buf, entry, cursor_row(buf))
    if entry.links then
      config.images.sync(buf, entry.links, entry.raw_row)
    end
  end, delay)
end

local function detach(buf, keep_cache)
  local entry = buffers[buf] or {}
  buffers[buf] = keep_cache and { cache = entry.cache or {} } or nil
  if entry.links then
    config.images.clear(buf)
  end
  if entry.version and api.nvim_buf_is_loaded(buf) then
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function on_event(event)
  local buf, name = event.buf, event.event
  if name == "BufUnload" or not is_nix(buf) then
    return detach(buf)
  end
  local entry = buffers[buf]
  local fresh = entry and entry.version == version(buf)
  if name == "BufLeave" or name == "WinLeave" then
    return fresh and reveal(buf, entry, nil)
  elseif not previewing(buf) then
    return detach(buf, true)
  end
  entry = entry or { cache = {} }
  buffers[buf] = entry
  if fresh then
    reveal(buf, entry, cursor_row(buf))
  end
  if not (fresh and name:find("^CursorMoved")) then
    schedule(buf, entry, name:find("^TextChanged") and 80 or 0)
  end
end

local function setup(opts)
  opts = opts or {}
  local marker = opts.marker or "|"
  assert(type(marker) == "string" and marker:match("^%S+$"), "marker must be nonempty and contain no whitespace")
  for buf in pairs(buffers) do
    detach(buf)
  end
  local group = api.nvim_create_augroup("NixCommentMarkdown", { clear = true })
  config = { pattern = "^#" .. vim.pesc(marker) .. "()[ \t]?()", rail = opts.rail ~= false }
  rail.setup(group)
  config.images = opts.images == true and require("nix_comment_markdown.images").new(config.rail) or nil
  local events = "FileType BufEnter BufWinEnter WinEnter WinClosed TabEnter WinResized ModeChanged BufLeave WinLeave BufUnload"
    .. " BufFilePost TextChanged TextChangedI TextChangedP CursorMoved CursorMovedI"
  api.nvim_create_autocmd(vim.split(events, " "), { group = group, callback = on_event })
  for _, win in ipairs(api.nvim_list_wins()) do
    on_event({ buf = api.nvim_win_get_buf(win), event = "BufWinEnter" })
  end
end

return { setup = setup }
