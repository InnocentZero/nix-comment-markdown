vim.opt.runtimepath:prepend({ assert(vim.env.TREESITTER_RTP), assert(vim.env.MARKVIEW_RTP), vim.uv.cwd() })
require("markview").setup({})

local api, fn = vim.api, vim.fn
local setup = require("nix_comment_markdown").setup
local rail = "NixCommentMarkdownRail"
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
local dir = fn.tempname()
fn.mkdir(dir, "p")
dir = assert(vim.uv.fs_realpath(dir))
local png = dir .. "/sample image.png"
fn.writefile({}, png)

local active, loads = {}, 0
local function render_image(self)
  active[self.id] = self
end
local function clear_image(self)
  active[self.id] = nil
end
package.loaded.image = {
  is_enabled = function()
    return true
  end,
  get_images = function()
    return vim.tbl_values(active)
  end,
  from_file = function(path, opts)
    loads = loads + 1
    assert(path == png and opts.buffer == buf and opts.window == win and opts.with_virtual_padding)
    return { id = opts.id, row = opts.y, render = render_image, clear = clear_image }
  end,
}

local fixture = [[
{
  #| # café **bold**
  #|
  #| | Item | Status |
  #| | ---- | ------ |
  #| | café | `yes`  |
  answer = 42; #| ## `trailing`
  #| ![local](sample%20image.png)
  #| ![remote](https://example.com/image.png)
  #| `![code](sample%20image.png)`
  # plain **comment**
  text = "#| **in a string**";
  /*
  #| **in a block comment**
  */
  #++ A Setext title
  #++ ------------
}]]
local source = vim.split(fixture, "\n")
api.nvim_buf_set_name(buf, dir .. "/test.nix")
api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.bo[buf].filetype = "nix"
vim.wo[win].conceallevel = 2
vim.wo[win].concealcursor = "n"
local adapter = require("nix_comment_markdown.markview")
local render, seen = adapter.render, {}
adapter.render = function(lines, ...)
  seen[#seen + 1] = lines
  return render(lines, ...)
end

local function edit(row, line)
  api.nvim_buf_set_lines(buf, row, row + 1, false, { line })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
end
setup({ images = true })
local ns = api.nvim_get_namespaces()["nix-comment-markdown"]
local function marks()
  return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local function row_marks(row)
  return vim.tbl_filter(function(mark)
    return mark[2] == row
  end, marks())
end
local function move(row, col)
  api.nvim_win_set_cursor(win, { row + 1, col or 0 })
  api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end
local function wait_for(check)
  assert(vim.wait(1000, check), "preview did not refresh")
end
local function wait_for_image(row)
  wait_for(function()
    local _, img = next(active)
    return (img and img.row) == row
  end)
end
wait_for_image(7)
assert(loads == 1, "only the local image should render")
assert(#seen == 3 and seen[1][2] == "" and seen[2][1] == "## `trailing`" and #seen[2] == 1)
assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), source) and #api.nvim_list_wins() == 1)

local bold, top, bottom, cell, rails = nil, nil, nil, nil, 0
local headings = {}
for _, mark in ipairs(marks()) do
  local _, row, col, d = unpack(mark)
  assert(row >= 1 and row <= 9, "decorations escaped the marked comments")
  if d.hl_group == rail then
    rails = rails + 1
    assert(d.end_col - col == 2 and fn.strdisplaywidth(d.conceal) == 2)
  elseif d.hl_group == "MarkviewHeading1" or d.hl_group == "MarkviewHeading2" then
    assert(d.hl_eol and d.end_row == row + 1 and d.end_col == 0)
    headings[row] = source[row + 1]:sub(col + 1)
  elseif row == 1 and d.hl_group == "@markup.strong" then
    bold = source[row + 1]:sub(col + 1, d.end_col)
  elseif d.virt_lines then
    local chunks = d.virt_lines[1]
    assert(col == 5 and chunks[2][1] == "  " and chunks[2][2] == rail)
    top = top or (row == 3 and d.virt_lines_above and vim.inspect(chunks):find("╭", 1, true))
    bottom = bottom or (row == 5 and not d.virt_lines_above and vim.inspect(chunks):find("╰", 1, true))
  elseif row == 5 and d.virt_text and d.virt_text[1][1] == "│" then
    cell = true
  end
end
assert(bold == "**bold**" and rails == 9 and top and bottom and cell)
assert(headings[1] == "# café **bold**" and headings[6] == "## `trailing`", "highlight should start after the rail")

local heading, table_row, trailing = row_marks(1), row_marks(3), row_marks(6)
move(1, 15)
assert(#row_marks(1) == 0 and vim.deep_equal(row_marks(3), table_row))
assert(vim.deep_equal(row_marks(6), trailing) and api.nvim_win_get_cursor(win)[2] == 15)
vim.cmd.redraw()
local pos = fn.screenpos(win, 2, 16)
assert(pos.curscol == fn.strdisplaywidth(source[2]:sub(1, 15)) + 1 and fn.screenstring(pos.row, pos.curscol) == "b")
assert(fn.screenstring(pos.row, 3) .. fn.screenstring(pos.row, 4) == "#|")
move(6, 19)
assert(#row_marks(1) == #heading and #row_marks(6) == 0)
move(7)
assert(#row_marks(6) == #trailing and #row_marks(7) == 0 and not next(active))
move(0)
assert(#row_marks(7) > 0 and next(active) and loads == 2 and #seen == 3)
assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), source))
local function row_styles(row)
  return vim.tbl_map(function(mark)
    return { mark[3], mark[4] }
  end, row_marks(row))
end
local table_footer = row_styles(5)
move(5)
assert(#row_marks(5) == 0)
move(0)
assert(vim.deep_equal(row_styles(5), table_footer), "moving away should restore the table footer and its styles")

move(1)
local insert_raw, ignore = false, vim.o.eventignore
api.nvim_create_autocmd("ModeChanged", {
  pattern = "*:i",
  once = true,
  callback = function()
    insert_raw = #marks() == 0 and not next(active)
    vim.o.eventignore = "ModeChanged,TextChanged"
  end,
})
api.nvim_feedkeys(vim.keycode("i<Esc>"), "nx", false)
assert(insert_raw, "Insert mode should show raw comments without images")
move(0)
wait_for_image(7)
vim.o.eventignore = ignore
assert(#row_marks(1) == #heading and #seen == 3, "moving after Insert should restore the preview from cache")
local loads_after_insert = loads
edit(10, "  # unrelated edit")
vim.wait(150)
assert(#seen == 3 and loads == loads_after_insert, "ordinary edits shouldn't rerender Markdown or images")
edit(7, "  #| no image")
wait_for_image(nil)
assert(#seen == 4)
edit(7, "  #| ![local](<sample image.png>)")
wait_for_image(7)
assert(loads == loads_after_insert + 1)

setup({ marker = "++" })
wait_for(function()
  return #seen == 6
end)
local setext
for _, mark in ipairs(marks()) do
  local _, row, col, d = unpack(mark)
  assert(row == 15 or row == 16, "only the new marker should render")
  if d.hl_group == rail then
    assert(d.end_col - col == 3 and fn.strdisplaywidth(d.conceal) == 2)
  elseif row == 15 and d.hl_group == "MarkviewHeading2" then
    assert(d.hl_eol and d.end_row == row + 1 and d.end_col == 0)
    setext = source[row + 1]:sub(col + 1)
  end
end
assert(setext == "A Setext title")

api.nvim_buf_set_lines(buf, 0, -1, false, { "{", "  #++ **across", "  #++ two lines**", "}" })
api.nvim_exec_autocmds("TextChanged", { buffer = buf })
move(2)
local function strong_on(row)
  for _, mark in ipairs(row_marks(row)) do
    if mark[4].hl_group == "@markup.strong" then
      return true
    end
  end
  return false
end
wait_for(function()
  return strong_on(1)
end)
assert(#row_marks(2) == 0, "a cross-line range must not decorate the cursor line")
move(1)
assert(#row_marks(1) == 0 and strong_on(2), "the other half of the range should still be rendered")
vim.cmd.new()
assert(strong_on(1) and strong_on(2), "leaving the buffer should restore the revealed line")
vim.cmd.close()
assert(#row_marks(1) == 0 and strong_on(2), "returning should reveal the cursor line again")
move(0)
local fence = { "{", "  #| ```lua", "  #| local x = 1", "  #|", "  #| ```", "}" }
api.nvim_buf_set_lines(buf, 0, -1, false, fence)
setup()
wait_for(function()
  return vim.iter(row_marks(2)):any(function(mark)
    return mark[3] == #fence[3] and mark[4].virt_text ~= nil
  end)
end)
assert(#api.nvim_list_wins() == 1)

require("markview").setup({ markdown = { code_blocks = { style = "simple" } } })
setup()
wait_for(function()
  return #row_marks(3) > 1
end)
api.nvim_set_hl(0, "MarkviewCode", { bg = "#ff3300", ctermbg = 196 })
vim.cmd.redraw()
local function attr(row, col)
  return fn.screenattr(fn.screenpos(win, row + 1, 1).row, col)
end
local fill = attr(2, 40)
assert(fill == attr(2, 6) and fill == attr(3, 40), "fill should reach past text and cover blank lines")
assert(fill ~= attr(2, 3) and fill ~= attr(5, 40), "fill should not color the rail or Nix source")
local code, blank = row_styles(2), row_styles(3)
move(3)
assert(vim.deep_equal(row_styles(2), code) and #row_marks(3) == 0)
move(0)
assert(vim.deep_equal(row_styles(3), blank))
vim.bo[buf].filetype = "lua"
assert(#marks() == 0)
fn.delete(dir, "rf")
print("Nix comment Markdown smoke test passed")
