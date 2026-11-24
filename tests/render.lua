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
  #| café **bold**
  #|
  #| | Item | Status |
  #| | ---- | ------ |
  #| | café | `yes`  |
  answer = 42; #| `trailing`
  #| ![local](sample%20image.png)
  #| ![remote](https://example.com/image.png)
  #| `![code](sample%20image.png)`
  # plain **comment**
  text = "#| **in a string**";
  /*
  #| **in a block comment**
  */
  #++ **another marker**
}]]
local source = vim.split(fixture, "\n")
api.nvim_buf_set_name(buf, dir .. "/test.nix")
api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.bo[buf].filetype = "nix"
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
assert(#seen == 3 and seen[1][2] == "" and seen[2][1] == "`trailing`" and #seen[2] == 1)
assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), source) and #api.nvim_list_wins() == 1)

local bold, top, bottom, cell, rails = nil, nil, nil, nil, 0
for _, mark in ipairs(marks()) do
  local _, row, col, d = unpack(mark)
  assert(row >= 1 and row <= 9, "decorations escaped the marked comments")
  if d.hl_group == rail then
    rails = rails + 1
    assert(d.end_col - col == 2 and fn.strdisplaywidth(d.conceal) == 2)
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
local insert_raw = false
api.nvim_create_autocmd("ModeChanged", {
  pattern = "*:i",
  once = true,
  callback = function()
    insert_raw = #marks() == 0 and not next(active)
  end,
})
api.nvim_feedkeys(vim.keycode("i<Esc>"), "nx", false)
assert(insert_raw, "Insert mode should show raw comments without images")
wait_for_image(7)
assert(#marks() > 0 and #seen == 3, "switching modes without editing should reuse the Markdown cache")
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
for _, mark in ipairs(marks()) do
  assert(mark[2] == 15, "only the new marker should render")
  if mark[4].hl_group == rail then
    assert(mark[4].end_col - mark[3] == 3 and fn.strdisplaywidth(mark[4].conceal) == 2)
  end
end
vim.bo[buf].filetype = "lua"
assert(#marks() == 0)
fn.delete(dir, "rf")
print("Nix comment Markdown smoke test passed")
