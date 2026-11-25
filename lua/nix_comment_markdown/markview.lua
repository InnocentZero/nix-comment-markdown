local api, ts = vim.api, vim.treesitter
local scratch, markdown
local inline_query = [[
  (strong_emphasis) @markup.strong
  (emphasis) @markup.italic
  (emphasis_delimiter) @delimiter
]]
local image_query = inline_query .. "(image (link_destination) @path)"
local table_window =
  { relative = "editor", row = 0, col = 0, width = 1, height = 1, hide = true, focusable = false, noautocmd = true }
local virtual_borders = { markdown = { tables = { use_virt_lines = true } } }
local style_keys = vim.split(
  "hl_group hl_eol hl_mode conceal url end_row end_col virt_text virt_text_pos virt_text_hide virt_lines virt_lines_above",
  " "
)

local function decoration(style, priority)
  local opts = { undo_restore = false, invalidate = true, priority = priority or style.priority or 110 }
  for _, key in ipairs(style_keys) do
    opts[key] = style[key]
  end
  return opts
end

local function render_content(content, tables)
  local renderer = require("markview.renderer")
  if #tables == 0 then
    return renderer.render(scratch, content)
  end
  local spec = require("markview.spec")
  local previous = spec.tmp_config
  local win = api.nvim_open_win(scratch, false, table_window)
  vim.wo[win].wrap = false
  spec.tmp_setup(vim.tbl_deep_extend("force", previous or spec.config, virtual_borders))
  local ok, err = pcall(renderer.render, scratch, content)
  spec.tmp_setup(previous)
  api.nvim_win_close(win, true)
  assert(ok, err)
end

local function read_marks(lines, tables)
  local marks = api.nvim_buf_get_extmarks(scratch, -1, 0, -1, { details = true })
  local ends = {}
  local ns = #tables > 0 and api.nvim_get_namespaces()["markview/markdown"]
  for _, item in ipairs(tables) do
    ends[item.range.row_end] = true
  end
  for i = 1, #marks do
    local _, row, col, details = unpack(marks[i])
    local opts, line = decoration(details, math.max(110, details.priority or 0)), lines[row + 1]
    if details.line_hl_group and line and line ~= "" then
      local opts = decoration({ hl_group = details.line_hl_group })
      opts.priority, opts.end_col = vim.hl.priorities.treesitter + 1, #line
      marks[#marks + 1] = { row, 0, opts }
    end
    if ends[row] and details.ns_id == ns and opts.virt_lines then
      row, opts.virt_lines_above = row - 1, false
    end
    marks[i] = { row, col, opts }
  end
  return marks
end

local function append_inline(marks, with_images)
  local inline = markdown:children().markdown_inline
  if not inline then
    return
  end
  local query = ts.query.parse("markdown_inline", with_images and image_query or inline_query)
  local images = with_images and {}
  for _, tree in pairs(inline:trees()) do
    for id, node in query:iter_captures(tree:root(), scratch) do
      local capture = query.captures[id]
      if capture == "path" then
        local row = node:parent():range()
        images[row] = images[row] or ts.get_node_text(node, scratch)
      else
        local row, col, last, last_col = node:range()
        local opts = decoration(capture == "delimiter" and { conceal = "" } or { hl_group = "@" .. capture })
        opts.end_row, opts.end_col = last, last_col
        marks[#marks + 1] = { row, col, opts }
      end
    end
  end
  return images
end

local function render(lines, with_images)
  if not scratch or not api.nvim_buf_is_loaded(scratch) then
    scratch = api.nvim_create_buf(false, true)
    markdown = assert(ts.get_parser(scratch, "markdown"))
  end
  api.nvim_buf_clear_namespace(scratch, -1, 0, -1)
  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  local content, sorted = require("markview.parser").parse(scratch, nil, nil, false)
  local tables = sorted.markdown and sorted.markdown.markdown_table or {}
  render_content(content, tables)
  local marks = read_marks(lines, tables)
  return marks, append_inline(marks, with_images)
end

return {
  decoration = decoration,
  render = render,
  in_preview_mode = function()
    return require("markview.actions").in_preview_mode()
  end,
}
