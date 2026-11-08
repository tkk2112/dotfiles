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
      -- Intentionally avoids Node/npm-backed servers. openscad-lsp is built
      -- with cargo, so only request it where cargo exists.
      ensure_installed = vim.list_extend({
        "ty",
        "ruff",
        "clangd",
        "zls",
        "lemminx",
        "lua_ls",
      }, vim.fn.executable("cargo") == 1 and { "openscad_lsp" } or {}),
      automatic_enable = false,
    },
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      local executables = require("config.executables")
      local project_lsp = require("config.project_lsp")

      vim.lsp.config("pylsp", {
        root_dir = project_lsp.root_dir("pylsp", {
          "pyproject.toml",
          "setup.py",
          "setup.cfg",
          "requirements.txt",
          "Pipfile",
          ".git",
        }, true),

        before_init = project_lsp.before_init("pylsp"),

        settings = {
          pylsp = {
            plugins = {
              autopep8 = { enabled = false },
              yapf = { enabled = false },
              pycodestyle = { enabled = false },
              pyflakes = { enabled = false },
              mccabe = { enabled = false },
            },
          },
        },
      })

      vim.lsp.config("ruff", {
        root_dir = project_lsp.root_dir("ruff", {
          "pyproject.toml",
          "ruff.toml",
          ".ruff.toml",
          ".git",
        }, true),

        before_init = project_lsp.before_init("ruff"),
      })

      vim.lsp.config("ty", {
        root_dir = project_lsp.root_dir("ty", {
          "ty.toml",
          "pyproject.toml",
          "setup.py",
          "setup.cfg",
          "requirements.txt",
          ".git",
        }, false),

        before_init = project_lsp.before_init("ty"),
      })

      local clangd_command = vim.deepcopy(vim.lsp.config.clangd.cmd)
      for _, argument in ipairs({
        "--background-index",
        "--clang-tidy",
      }) do
        if not vim.tbl_contains(clangd_command, argument) then
          table.insert(clangd_command, argument)
        end
      end

      -- Build systems put compile_commands.json deep inside build folders,
      -- where clangd does not look; pass the newest one explicitly.
      local compile_commands = require("config.compile_commands")

      vim.lsp.config("clangd", {
        cmd = project_lsp.command("clangd", clangd_command, compile_commands.extend_clangd_command),
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

      -- Library folders OpenSCAD searches for include/use, so completion and
      -- go-to-definition also work for installed libraries (BOSL2, …).
      local openscad_libraries = vim.tbl_filter(
        function(path)
          return vim.fn.isdirectory(path) == 1
        end,
        vim.list_extend(vim.split(vim.env.OPENSCADPATH or "", ":", { trimempty = true }), {
          vim.fn.expand("~/Documents/OpenSCAD/libraries"),
          vim.fn.expand("~/.local/share/OpenSCAD/libraries"),
        })
      )

      vim.lsp.config("openscad_lsp", {
        cmd = { "openscad-lsp", "--stdio", "--indent", "    " },
        settings = {
          openscad = {
            search_paths = table.concat(openscad_libraries, ":"),
          },
        },
      })

      for _, server in ipairs({ "pylsp", "ruff", "ty", "clangd", "zls", "lemminx", "lua_ls", "cmake", "openscad_lsp" }) do
        vim.lsp.enable(server)
      end
    end,
  },
}
