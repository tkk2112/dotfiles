local tmux_nav = require("config.tmux_nav")

describe("tmux navigation", function()
  before_each(function()
    vim.cmd("tabonly!")
    vim.cmd("only!")

    -- Start every test with a normal scratch buffer.
    vim.cmd("enew!")
  end)

  after_each(function()
    vim.cmd("tabonly!")
    vim.cmd("only!")
  end)

  describe("navigation title", function()
    it("advertises no available directions with one window", function()
      assert.are.equal("dotmux/1:L0D0U0R0", tmux_nav.navigation_title())
    end)

    it("advertises right from the left side of a vertical split", function()
      vim.cmd("vsplit")
      vim.cmd("wincmd h")

      assert.are.equal("dotmux/1:L0D0U0R1", tmux_nav.navigation_title())
    end)

    it("advertises left from the right side of a vertical split", function()
      vim.cmd("vsplit")
      vim.cmd("wincmd l")

      assert.are.equal("dotmux/1:L1D0U0R0", tmux_nav.navigation_title())
    end)

    it("advertises down from the top of a horizontal split", function()
      vim.cmd("split")
      vim.cmd("wincmd k")

      assert.are.equal("dotmux/1:L0D1U0R0", tmux_nav.navigation_title())
    end)

    it("advertises up from the bottom of a horizontal split", function()
      vim.cmd("split")
      vim.cmd("wincmd j")

      assert.are.equal("dotmux/1:L0D0U1R0", tmux_nav.navigation_title())
    end)

    it("advertises multiple available directions", function()
      vim.cmd("vsplit")
      vim.cmd("wincmd l")
      vim.cmd("split")
      vim.cmd("wincmd k")

      assert.are.equal("dotmux/1:L1D1U0R0", tmux_nav.navigation_title())
    end)
  end)

  describe("move", function()
    it("moves between Neovim windows", function()
      vim.cmd("vsplit")
      vim.cmd("wincmd h")

      local left = vim.api.nvim_get_current_win()

      tmux_nav.move("right")

      assert.not_equal(left, vim.api.nvim_get_current_win())
      assert.are.equal("dotmux/1:L1D0U0R0", tmux_nav.navigation_title())
    end)

    it("stays in the current window when there is nowhere to move", function()
      local before = vim.api.nvim_get_current_win()

      tmux_nav.move("right")

      assert.are.equal(before, vim.api.nvim_get_current_win())
      assert.are.equal("dotmux/1:L0D0U0R0", tmux_nav.navigation_title())
    end)

    it("does not move for an unknown direction", function()
      vim.cmd("vsplit")
      vim.cmd("wincmd h")

      local before = vim.api.nvim_get_current_win()

      tmux_nav.move("sideways")

      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)
  end)
end)
