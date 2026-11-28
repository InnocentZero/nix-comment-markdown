local api, ts = vim.api, vim.treesitter
local scratch, markdown
local inline_query = [[
  (strong_emphasis) @markup.strong
  (emphasis) @markup.italic
  (emphasis_delimiter) @delimiter
  (image (link_destination) @path)
]]
local window = { relative = "editor", row = 0, col = 0, height = 1, hide = true, focusable = false, noautocmd = true }
window.style = "minimal"
local virtual_borders = { markdown = { tables = { use_virt_lines = true } } }

local function run_markview(width)
  local spec = require("markview.spec")
  local previous = spec.tmp_config
  window.width = width
  local win = api.nvim_open_win(scratch, false, window)
  vim.wo[win].wrap = false
  spec.tmp_setup(vim.tbl_deep_extend("force", previous or spec.config, virtual_borders))
  local ok, err = pcall(api.nvim_win_call, win, function()
    require("markview.renderer").render(scratch, require("markview.parser").parse(scratch, nil, nil, false))
  end)
  spec.tmp_setup(previous)
  api.nvim_win_close(win, true)
  assert(ok, err)
end

local function render(lines, width, with_images)
  if not (scratch and api.nvim_buf_is_loaded(scratch)) then
    scratch, markdown = api.nvim_create_buf(false, true), nil
  end
  markdown = markdown or assert(ts.get_parser(scratch, "markdown"))
  api.nvim_buf_clear_namespace(scratch, -1, 0, -1)
  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  run_markview(width)
  local marks, images = {}, with_images and {} or nil
  for _, mark in ipairs(api.nvim_buf_get_extmarks(scratch, -1, 0, -1, { details = true })) do
    local _, row, col, details = unpack(mark)
    details.priority = math.max(110, details.priority or 0)
    if details.line_hl_group then
      local fill = { hl_group = details.line_hl_group, hl_eol = true, end_row = row + 1, end_col = 0, priority = 101 }
      marks[#marks + 1], details.line_hl_group = { row, 0, fill }, nil
    end
    marks[#marks + 1] = { row, col, details }
  end
  markdown:parse(true)
  local query = ts.query.parse("markdown_inline", inline_query)
  for _, tree in pairs(markdown:children().markdown_inline and markdown:children().markdown_inline:trees() or {}) do
    for id, node in query:iter_captures(tree:root(), scratch) do
      local capture, row, col, last, last_col = query.captures[id], node:range()
      if capture ~= "path" then
        local details = capture == "delimiter" and { conceal = "" } or { hl_group = "@" .. capture }
        details.end_row, details.end_col, details.priority = last, last_col, 110
        marks[#marks + 1] = { row, col, details }
      elseif images then
        row = node:parent():range()
        images[row] = images[row] or ts.get_node_text(node, scratch)
      end
    end
  end
  return marks, images
end

return { render = render }
