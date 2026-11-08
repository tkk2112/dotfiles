#!/usr/bin/env -S nvim -l

local repo_root = vim.fs.normalize(vim.uv.cwd())
local config_root = vim.fs.joinpath(repo_root, "home", "dot_config", "nvim")
local test_root = vim.fs.joinpath(repo_root, ".tests")
local lazy_path = vim.fs.joinpath(test_root, "lazy", "lazy.nvim")

vim.env.LAZY_STDPATH = test_root

if not vim.uv.fs_stat(lazy_path) then
  vim.fn.mkdir(vim.fs.dirname(lazy_path), "p")

  local result = vim
    .system({
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=stable",
      "https://github.com/folke/lazy.nvim.git",
      lazy_path,
    }, {
      text = true,
    })
    :wait()

  assert(result.code == 0, result.stderr)
end

vim.opt.rtp:prepend(lazy_path)
vim.opt.rtp:prepend(config_root)

-- luassert and its dependency say are plain Lua. Load them from their git
-- checkouts instead of building LuaRocks packages, which needs hererocks to
-- download and compile Lua 5.1 and breaks in CI containers.
local plugin_root = vim.fs.joinpath(test_root, "data", "nvim", "lazy")

package.path = table.concat({
  package.path,
  plugin_root .. "/say/src/?.lua",
  plugin_root .. "/say/src/?/init.lua",
}, ";")

-- luassert's rockspec maps module luassert.<name> to src/<name>.lua.
table.insert(package.loaders, 2, function(name)
  if name ~= "luassert" and not vim.startswith(name, "luassert.") then
    return nil
  end

  local relative = name == "luassert" and "init" or (name:sub(#"luassert." + 1):gsub("%.", "/"))
  local source = plugin_root .. "/luassert/src/"

  for _, candidate in ipairs({ source .. relative .. ".lua", source .. relative .. "/init.lua" }) do
    if vim.uv.fs_stat(candidate) then
      return assert(loadfile(candidate))
    end
  end

  return "\n\tno luassert file for " .. name
end)

package.preload["config.llm.capabilities"] = function()
  return {
    providers = {
      "codex",
      "claude",
    },

    engines = {
      "mlx",
      "llama_cpp",
    },

    features = {
      "completion",
    },
  }
end

require("lazy.minit").setup({
  rocks = {
    enabled = false,
  },
  spec = {
    { dir = config_root },
    "lunarmodules/say",
  },
})
