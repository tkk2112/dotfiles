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

require("lazy.minit").setup({
  spec = {
    { dir = config_root },
  },
})
