local languages = {
  -- Primary programming languages.
  "c",
  "cpp",
  "python",
  "zig",

  -- Hardware and assembly.
  "asm",
  "nasm",
  "systemverilog",

  -- Build systems.
  "cmake",
  "make",
  "meson",
  "ninja",

  -- Structured data and configuration.
  "json",
  "toml",
  "yaml",
  "xml",

  -- Web.
  "css",
  "html",
  "javascript",
  "regex",

  -- Neovim configuration and Tree-sitter queries.
  "lua",
  "query",
  "vim",
  "vimdoc",

  -- Shell and terminal configuration.
  "bash",
  "zsh",
  "ssh_config",
  "tmux",

  -- Git and patch files.
  "diff",
  "git_config",
  "git_rebase",
  "gitattributes",
  "gitcommit",
  "gitignore",

  -- Documentation.
  "markdown",
  "markdown_inline",
}

-- These provide shared query files rather than standalone parsers.
--
-- JavaScript inherits from ecma and jsx. HTML-related queries may inherit
-- from html_tags. Installing them explicitly prevents incomplete query sets
-- on a new machine or after registry changes.
local query_dependencies = {
  "ecma",
  "html_tags",
  "jsx",
}

local install_targets = vim.list_extend(vim.deepcopy(languages), query_dependencies)

return {
  {
    "neovim-treesitter/nvim-treesitter",

    dependencies = {
      "neovim-treesitter/treesitter-parser-registry",
    },

    -- The current nvim-treesitter rewrite does not support lazy-loading.
    lazy = false,

    build = function()
      local treesitter = require("nvim-treesitter")

      -- Install anything missing, then update already-installed parsers and
      -- query packages. The longer timeout accommodates clean CI installs.
      treesitter.install(install_targets):wait(600000)
      treesitter.update(install_targets):wait(600000)
    end,

    config = function()
      local group = vim.api.nvim_create_augroup("dotfiles_treesitter", { clear = true })

      -- XSLT uses the XML parser.
      vim.treesitter.language.register("xml", "xslt")

      -- Start Tree-sitter for any filetype with an installed parser. Missing
      -- parsers are ignored so uncommon filetypes still open normally.
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "*",
        callback = function(event)
          pcall(vim.treesitter.start, event.buf)
        end,
      })
    end,
  },
}
