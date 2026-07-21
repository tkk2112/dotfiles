require("config.options")
require("config.filetypes")

-- Keep lazy.nvim initialization here
require("config.lazy")

local project = require("config.project")
local project_sessions = require("config.project_sessions")
local project_settings = require("config.project_settings")

project_settings.setup()

project_sessions.setup(function()
  return project_settings.root(0)
end)

project.setup()

require("config.autosave").setup()
require("config.format").setup()
require("config.lsp_ui").setup()
require("config.language_docs").setup()

require("config.theme").setup()
require("config.theme_dev").setup()

require("config.quickfix_watch").setup()
require("config.zsh_diagnostics").setup()

require("config.keymaps").setup()
