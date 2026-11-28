local api, ts = vim.api, vim.treesitter
local rail = require("nix_comment_markdown.rail")

local function options(details, continuation)
  local opts = { undo_restore = false, invalidate = true }
  for key, value in pairs(details) do
    local skip = key == "ns_id" or key == "invalid" or key:find("gravity$") or key:find("^sign_")
    if not (skip or continuation and key:find("^virt_")) then
      opts[key] = value
    end
  end
  return opts
end

local function find(buf, pattern)
  local parser, err = ts.get_parser(buf, "nix")
  if not parser then
    return nil, err
  end
  local lines, blocks, block, next_row = api.nvim_buf_get_lines(buf, 0, -1, false), {}, nil, nil
  for _, node in ts.query.parse("nix", "(comment) @c"):iter_captures(parser:parse()[1]:root(), buf) do
    local row, col, last = node:range()
    local line = row == last and lines[row + 1] or ""
    local marker_end, text_start = line:match(pattern, col + 1)
    if text_start then
      local standalone = not line:sub(1, col):find("%S")
      if row ~= next_row or not standalone or col ~= block.col then
        block = { row = row, col = col, lines = {} }
        blocks[#blocks + 1] = block
      end
      next_row = standalone and row + 1 or nil
      local prefix, text = line:sub(1, text_start - 1), line:sub(text_start)
      block.lines[#block.lines + 1] = { prefix = prefix, text = text, marker_start = col, marker_end = marker_end - 1 }
    end
  end
  return blocks
end

local function place(buf, ns, block, marks, show_rail)
  local last = #block.lines - 1
  for i, line in ipairs(show_rail and block.lines or {}) do
    api.nvim_buf_set_extmark(buf, ns, block.row + i - 1, line.marker_start, rail.mark(line))
  end
  for _, mark in ipairs(marks) do
    local anchor, col, details = unpack(mark)
    local first, finish = math.min(anchor, last), details.end_row or anchor
    for row = first, math.min(finish, last) do
      local line = block.lines[row + 1]
      local offset, length = #line.prefix, #line.text
      local stop = row == finish and math.min(details.end_col or length, length) or length
      local fill = details.hl_eol and row < finish
      if row == first or stop > 0 or fill then
        local opts = options(details, row ~= first)
        opts.end_row = fill and block.row + row + 1 or nil
        opts.end_col = fill and 0 or details.end_col and offset + stop
        if opts.virt_lines then
          local indent = rail.indent(line, show_rail)
          opts.virt_lines = vim.tbl_map(function(chunks)
            return vim.list_extend(vim.list_extend({}, indent), chunks)
          end, details.virt_lines)
          opts.virt_lines_above = anchor <= last and details.virt_lines_above or false
        end
        api.nvim_buf_set_extmark(buf, ns, block.row + row, offset + (row == first and math.min(col, length) or 0), opts)
      end
    end
  end
end

return { find = find, place = place, options = options }
