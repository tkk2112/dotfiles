local languages = {
  -- Primary programming languages.
  "c",
  "cpp",
  "python",
  "zig",

  -- 3D modelling.
  "openscad",

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

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",

    lazy = false,

    init = function()
      -- Not in nvim-treesitter's parser list; use the official grammar and
      -- its Neovim highlight/indent queries.
      vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function()
          require("nvim-treesitter.parsers").openscad = {
            install_info = {
              url = "https://github.com/openscad/tree-sitter-openscad",
              revision = "27329e1905a346131d6beb6e2a32fed8cd7e2816",
              queries = "queries",
            },
          }
        end,
      })
    end,

    build = function()
      local treesitter = require("nvim-treesitter")

      -- Install anything missing, then update already-installed parsers.
      -- The longer timeout accommodates clean CI installs.
      treesitter.install(languages):wait(600000)
      treesitter.update(languages):wait(600000)
    end,

    config = function()
      local group = vim.api.nvim_create_augroup("dotfiles_treesitter", { clear = true })

      -- XSLT uses the XML parser.
      vim.treesitter.language.register("xml", "xslt")

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
