local GROUP, WIDTH = "NixCommentMarkdownRail", 2
local width = vim.fn.strdisplaywidth

local function highlight()
  local dark = vim.o.background == "dark"
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or (dark and 0x181818 or 0xFFFFFF)
  local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
  local shift = math.max(r, g, b) < 24 and 12 or -12
  local color = math.max(0, r + shift) * 65536 + math.max(0, g + shift) * 256 + math.max(0, b + shift)
  local cterm = dark and 235 or 250
  vim.api.nvim_set_hl(0, GROUP, { fg = color, bg = color, ctermfg = cterm, ctermbg = cterm })
end

local function setup(augroup)
  highlight()
  vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, callback = highlight })
end

local function indent(line, enabled)
  if not enabled then
    return { { string.rep(" ", width(line.prefix)) } }
  end
  local before = width(line.prefix:sub(1, line.marker_start))
  local after = width(line.prefix:sub(line.marker_end + 1), before + WIDTH)
  return { { string.rep(" ", before) }, { string.rep(" ", WIDTH), GROUP }, { string.rep(" ", after) } }
end

local function prefix_width(line, enabled)
  return width(table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, indent(line, enabled))))
end

local function mark(line)
  return {
    end_col = line.marker_end,
    conceal = "　",
    hl_group = GROUP,
    priority = 10000,
    undo_restore = false,
    invalidate = true,
  }
end

return { setup = setup, indent = indent, width = prefix_width, mark = mark }
