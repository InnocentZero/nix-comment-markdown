local group = "NixCommentMarkdownRail"
local cells = { "  ", group }

local function highlight()
  local dark = vim.o.background == "dark"
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or (dark and 0x181818 or 0xFFFFFF)
  local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
  local shift = math.max(r, g, b) < 24 and 12 or -12
  local color = math.max(0, r + shift) * 65536 + math.max(0, g + shift) * 256 + math.max(0, b + shift)
  local cterm = dark and 235 or 250
  vim.api.nvim_set_hl(0, group, { fg = color, bg = color, ctermfg = cterm, ctermbg = cterm })
end

local function chunks(prefix, show_rail)
  local display_width = vim.fn.strdisplaywidth
  if show_rail == false then
    return { { string.rep(" ", display_width(prefix.raw)) } }
  end
  local width = display_width(prefix.raw:sub(1, prefix.marker_start))
  local sep = display_width(prefix.raw:sub(prefix.marker_end + 1), width + 2)
  return { { string.rep(" ", width) }, cells, { string.rep(" ", sep) } }
end

local function setup(augroup)
  highlight()
  vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, callback = highlight })
  return { conceal = "　", hl_group = group, priority = 10000, undo_restore = false, invalidate = true }
end

return { setup = setup, prefix = chunks }
