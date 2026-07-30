return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },

  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      -- Intentionally avoids Node/npm-backed servers.
      ensure_installed = {
        "pylsp",
        "clangd",
        "zls",
        "lemminx",
        "lua_ls",
      },
      automatic_enable = false,
    },
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      local executables = require("config.executables")
      local project_lsp = require("config.project_lsp")

      local clangd_command = vim.deepcopy(vim.lsp.config.clangd.cmd)

      for _, argument in ipairs({
        "--background-index",
        "--clang-tidy",
      }) do
        if not vim.tbl_contains(clangd_command, argument) then
          table.insert(clangd_command, argument)
        end
      end

      vim.lsp.config("clangd", {
        cmd = project_lsp.command("clangd", clangd_command),
      })

      local cmake_language_server = executables.find("cmake-language-server", {
        "/opt/homebrew/bin/cmake-language-server",
      })

      vim.lsp.config("cmake", {
        cmd = { cmake_language_server },
        filetypes = { "cmake" },
        root_markers = {
          "CMakePresets.json",
          "CTestConfig.cmake",
          "CMakeLists.txt",
          ".git",
        },
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
          },
        },
      })

      for _, server in ipairs({ "pylsp", "clangd", "zls", "lemminx", "lua_ls", "cmake" }) do
        vim.lsp.enable(server)
      end
    end,
  },
}
