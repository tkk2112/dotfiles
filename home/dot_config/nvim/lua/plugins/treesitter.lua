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

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",

    lazy = false,

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
