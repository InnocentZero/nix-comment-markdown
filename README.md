# nix-comment-markdown

Preview Markdown inside `#|` Nix comments with [Markview](https://github.com/OXY2DEV/markview.nvim):

```nix
#| **Markdown** in a Nix comment.
{ answer = 42; }
```

You need Neovim 0.12+, Markview, and the `nix`, `markdown`, and `markdown_inline` Tree-sitter parsers. Add this plugin to your `runtimepath`, set up Markview, then call:

```lua
require("nix_comment_markdown").setup()
```

In Nix windows, set `conceallevel=2` and `concealcursor=n`, and exclude `nix` from Markview's own preview (including any custom `preview.condition`).

Options: `marker = ":"` for `#:`, `rail = false` to keep `#|` visible, or `images = true` for local images with [image.nvim](https://github.com/3rd/image.nvim).
