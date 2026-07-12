local M = {}

local C_FAMILY = { "c", "cpp" }

local function set(group, options)
  vim.api.nvim_set_hl(0, group, options)
end

local function set_all(groups)
  for group, options in pairs(groups) do
    set(group, options)
  end
end

local function set_for_filetypes(group, options, filetypes)
  for _, filetype in ipairs(filetypes or C_FAMILY) do
    set(group .. "." .. filetype, options)
  end
end

local function set_captures(captures, filetypes)
  for group, options in pairs(captures) do
    set(group, options)

    if filetypes then
      set_for_filetypes(group, options, filetypes)
    end
  end
end

local function roles_for(mode, palette)
  if mode == "light" then
    return {
      text = "#1F1F1F",
      text_dim = "#3B3B3B",
      comment = "#008000",

      keyword = "#0000FF",
      preprocessor = "#008000",
      namespace = "#7A3E9D",
      type = "#267F99",
      type_parameter = "#AF00DB",
      concept = "#001080",
      concept_bold = true,

      callable = "#795E26",
      variable = "#001080",
      parameter = "#001080",
      member = "#001080",
      constant = "#0070C1",

      string = "#A31515",
      number = "#098658",
      boolean = "#0000FF",
      macro = "#0000FF",
      special = "#AF00DB",

      operator = "#1F1F1F",
      punctuation = "#1F1F1F",
      punctuation_dim = "#616161",

      diagnostic_error = "#9A4A4A",
      diagnostic_error_strong = "#C42B2B",
      diagnostic_warn = "#8A6D1D",
      diagnostic_info = "#2563A5",
      diagnostic_hint = "#397A78",

      cursor_normal = "#005FB8",
      cursor_insert = "#16825D",
      cursor_replace = "#C42B2B",
      cursor_text = "#FFFFFF",
      cursorline = "#F0F4F8",

      declaration_bold = false,
      comment_italic = true,
      type_parameter_italic = true,
    }
  end
  local dark = {
    -- Language structure.
    keyword = palette.purple,
    preprocessor = palette.red,

    -- Named symbols.
    namespace = "#63B7B0",
    type = palette.yellow,
    type_parameter = "#D16DFF",
    callable = "#74A9E2",
    concept = "#D8B172",

    -- Values.
    parameter = "#D99A68",
    member = "#78BEC7",
    constant = "#E0AF67",
    boolean = "#D77FA1",

    -- Supporting syntax.
    special = "#B89BE5",
    operator = "#8BA6B3",
  }

  return {
    text = palette.foreground,
    text_dim = palette.foreground_dim,
    comment = palette.muted,

    keyword = dark.keyword,
    preprocessor = dark.preprocessor,

    namespace = dark.namespace,
    type = dark.type,
    type_parameter = dark.type_parameter,
    concept = dark.concept,
    concept_bold = true,

    callable = dark.callable,

    variable = palette.foreground,
    parameter = dark.parameter,
    member = dark.member,
    constant = dark.constant,

    string = palette.green,
    number = palette.orange,
    boolean = dark.boolean,

    macro = dark.preprocessor,
    special = dark.special,

    operator = dark.operator,
    punctuation = palette.foreground_dim,
    punctuation_dim = palette.muted,

    diagnostic_error = palette.red,
    diagnostic_error_strong = palette.red,
    diagnostic_warn = palette.yellow,
    diagnostic_info = palette.blue,
    diagnostic_hint = palette.cyan,

    cursor_normal = palette.blue,
    cursor_insert = palette.green,
    cursor_replace = palette.red,
    cursor_text = palette.background,
    cursorline = palette.surface,

    declaration_bold = true,
    comment_italic = true,
    type_parameter_italic = true,
  }
end

local function apply_ui(palette, roles)
  set_all({
    Normal = {
      fg = palette.foreground,
      bg = palette.background,
    },
    NormalNC = {
      fg = palette.foreground_dim,
      bg = palette.background,
    },
    NormalFloat = {
      fg = palette.foreground,
      bg = palette.surface,
    },
    FloatBorder = {
      fg = palette.border,
      bg = palette.surface,
    },
    FloatTitle = {
      fg = roles.callable,
      bg = palette.surface,
      bold = true,
    },

    Cursor = {
      fg = roles.cursor_text,
      bg = roles.cursor_normal,
    },
    lCursor = {
      fg = roles.cursor_text,
      bg = roles.cursor_normal,
    },
    CursorInsert = {
      fg = roles.cursor_text,
      bg = roles.cursor_insert,
    },
    CursorReplace = {
      fg = roles.cursor_text,
      bg = roles.cursor_replace,
    },
    TermCursor = {
      fg = roles.cursor_text,
      bg = roles.cursor_normal,
    },
    TermCursorNC = {
      fg = palette.foreground_dim,
      bg = palette.surface_alt,
    },

    CursorLine = {
      bg = roles.cursorline,
    },
    CursorColumn = {
      bg = roles.cursorline,
    },
    CursorLineNr = {
      fg = roles.cursor_normal,
      bold = true,
    },
    LineNr = {
      fg = palette.muted,
    },
    SignColumn = {
      fg = palette.muted,
      bg = palette.background,
    },
    FoldColumn = {
      fg = palette.muted,
      bg = palette.background,
    },
    Folded = {
      fg = palette.muted,
      bg = palette.surface,
    },
    ColorColumn = {
      bg = palette.surface,
    },

    Visual = {
      bg = palette.selection,
    },
    Search = {
      fg = palette.background,
      bg = palette.yellow,
    },
    IncSearch = {
      fg = palette.background,
      bg = palette.orange,
      bold = true,
    },
    CurSearch = {
      fg = palette.background,
      bg = palette.orange,
      bold = true,
    },
    MatchParen = {
      fg = roles.text,
      bg = palette.surface_alt,
      bold = true,
    },

    Pmenu = {
      fg = palette.foreground,
      bg = palette.surface,
    },
    PmenuSel = {
      fg = palette.background,
      bg = roles.cursor_normal,
      bold = true,
    },
    PmenuSbar = {
      bg = palette.surface_alt,
    },
    PmenuThumb = {
      bg = palette.muted,
    },

    StatusLine = {
      fg = palette.foreground,
      bg = palette.surface_alt,
    },
    StatusLineNC = {
      fg = palette.muted,
      bg = palette.surface,
    },
    WinBar = {
      fg = palette.foreground_dim,
      bg = palette.background,
    },
    WinBarNC = {
      fg = palette.muted,
      bg = palette.background,
    },
    TabLine = {
      fg = palette.muted,
      bg = palette.surface,
    },
    TabLineFill = {
      bg = palette.surface,
    },
    TabLineSel = {
      fg = palette.background,
      bg = roles.cursor_normal,
      bold = true,
    },

    WinSeparator = {
      fg = palette.border,
    },
    NonText = {
      fg = palette.muted,
    },
    Whitespace = {
      fg = palette.border,
    },
    EndOfBuffer = {
      fg = palette.background,
    },

    LspReferenceText = {
      bg = palette.selection,
    },
    LspReferenceRead = {
      bg = palette.selection,
    },
    LspReferenceWrite = {
      bg = palette.selection,
      bold = true,
    },
    LspInlayHint = {
      fg = palette.muted,
      bg = palette.surface,
      italic = true,
    },
  })
end

local function apply_syntax(roles)
  set_all({
    Comment = {
      fg = roles.comment,
      italic = roles.comment_italic,
    },
    Constant = {
      fg = roles.constant,
    },
    String = {
      fg = roles.string,
    },
    Character = {
      fg = roles.string,
    },
    Number = {
      fg = roles.number,
    },
    Boolean = {
      fg = roles.boolean,
    },
    Float = {
      fg = roles.number,
    },

    Identifier = {
      fg = roles.variable,
    },
    Function = {
      fg = roles.callable,
    },

    Statement = {
      fg = roles.keyword,
    },
    Conditional = {
      fg = roles.keyword,
    },
    Repeat = {
      fg = roles.keyword,
    },
    Label = {
      fg = roles.keyword,
    },
    Operator = {
      fg = roles.operator,
    },
    Keyword = {
      fg = roles.keyword,
    },
    Exception = {
      fg = roles.keyword,
    },

    PreProc = {
      fg = roles.preprocessor,
    },
    Include = {
      fg = roles.preprocessor,
    },
    Define = {
      fg = roles.preprocessor,
    },
    Macro = {
      fg = roles.macro,
    },

    Type = {
      fg = roles.type,
    },
    StorageClass = {
      fg = roles.keyword,
    },
    Structure = {
      fg = roles.keyword,
    },
    Typedef = {
      fg = roles.type,
    },

    Special = {
      fg = roles.special,
    },
    SpecialChar = {
      fg = roles.special,
    },
    Delimiter = {
      fg = roles.punctuation,
    },

    Title = {
      fg = roles.callable,
      bold = true,
    },
    Underlined = {
      underline = true,
    },
    Todo = {
      fg = roles.keyword,
      bold = true,
    },
  })
end

local function apply_diagnostics(roles)
  set_all({
    DiagnosticError = {
      fg = roles.diagnostic_error,
    },
    DiagnosticWarn = {
      fg = roles.diagnostic_warn,
    },
    DiagnosticInfo = {
      fg = roles.diagnostic_info,
    },
    DiagnosticHint = {
      fg = roles.diagnostic_hint,
    },
    DiagnosticOk = {
      fg = roles.cursor_insert,
    },

    DiagnosticVirtualTextError = {
      fg = roles.diagnostic_error,
    },
    DiagnosticVirtualTextWarn = {
      fg = roles.diagnostic_warn,
    },
    DiagnosticVirtualTextInfo = {
      fg = roles.diagnostic_info,
    },
    DiagnosticVirtualTextHint = {
      fg = roles.diagnostic_hint,
    },

    DiagnosticFloatingError = {
      fg = roles.diagnostic_error,
    },
    DiagnosticFloatingWarn = {
      fg = roles.diagnostic_warn,
    },
    DiagnosticFloatingInfo = {
      fg = roles.diagnostic_info,
    },
    DiagnosticFloatingHint = {
      fg = roles.diagnostic_hint,
    },

    DiagnosticSignError = {
      fg = roles.diagnostic_error_strong,
    },
    DiagnosticSignWarn = {
      fg = roles.diagnostic_warn,
    },
    DiagnosticSignInfo = {
      fg = roles.diagnostic_info,
    },
    DiagnosticSignHint = {
      fg = roles.diagnostic_hint,
    },

    DiagnosticUnderlineError = {
      undercurl = true,
      sp = roles.diagnostic_error_strong,
    },
    DiagnosticUnderlineWarn = {
      undercurl = true,
      sp = roles.diagnostic_warn,
    },
    DiagnosticUnderlineInfo = {
      undercurl = true,
      sp = roles.diagnostic_info,
    },
    DiagnosticUnderlineHint = {
      undercurl = true,
      sp = roles.diagnostic_hint,
    },

    DiagnosticVirtualLinesError = {
      fg = roles.diagnostic_error,
    },
    DiagnosticDeprecated = {
      strikethrough = true,
      sp = roles.comment,
    },
    DiagnosticUnnecessary = {
      fg = roles.comment,
    },
  })
end

local function apply_diffs(palette)
  set_all({
    DiffAdd = {
      fg = palette.green,
      bg = palette.surface,
    },
    DiffChange = {
      fg = palette.yellow,
      bg = palette.surface,
    },
    DiffDelete = {
      fg = palette.red,
      bg = palette.surface,
    },
    DiffText = {
      fg = palette.background,
      bg = palette.blue,
      bold = true,
    },
  })
end

local function apply_treesitter(roles)
  local captures = {
    ["@comment"] = {
      fg = roles.comment,
      italic = roles.comment_italic,
    },

    ["@string"] = { fg = roles.string },
    ["@string.escape"] = { fg = roles.special },
    ["@character"] = { fg = roles.string },
    ["@number"] = { fg = roles.number },
    ["@number.float"] = { fg = roles.number },
    ["@boolean"] = { fg = roles.boolean },

    ["@constant"] = { fg = roles.constant },
    ["@constant.builtin"] = { fg = roles.constant },
    ["@constant.macro"] = { fg = roles.macro },

    ["@variable"] = { fg = roles.variable },
    ["@variable.builtin"] = { fg = roles.special },
    ["@variable.parameter"] = { fg = roles.parameter },
    ["@variable.member"] = { fg = roles.member },
    ["@property"] = { fg = roles.member },

    ["@module"] = { fg = roles.namespace },
    ["@module.builtin"] = { fg = roles.namespace },
    ["@namespace"] = { fg = roles.namespace },

    ["@type"] = { fg = roles.type },
    ["@type.builtin"] = { fg = roles.type },
    ["@type.definition"] = { fg = roles.type },
    ["@type.parameter"] = {
      fg = roles.type_parameter,
      italic = roles.type_parameter_italic,
    },

    ["@function"] = { fg = roles.callable },
    ["@function.call"] = { fg = roles.callable },
    ["@function.builtin"] = { fg = roles.callable },
    ["@function.method"] = { fg = roles.callable },
    ["@function.method.call"] = { fg = roles.callable },
    ["@method"] = { fg = roles.callable },
    ["@method.call"] = { fg = roles.callable },
    ["@constructor"] = { fg = roles.type },

    ["@keyword"] = { fg = roles.keyword },
    ["@keyword.function"] = { fg = roles.keyword },
    ["@keyword.type"] = { fg = roles.keyword },
    ["@keyword.modifier"] = { fg = roles.keyword },
    ["@keyword.conditional"] = { fg = roles.keyword },
    ["@keyword.repeat"] = { fg = roles.keyword },
    ["@keyword.return"] = { fg = roles.keyword },
    ["@keyword.exception"] = { fg = roles.keyword },
    ["@keyword.operator"] = { fg = roles.keyword },
    ["@keyword.directive"] = { fg = roles.preprocessor },
    ["@keyword.directive.define"] = { fg = roles.preprocessor },

    ["@operator"] = { fg = roles.operator },

    ["@punctuation.delimiter"] = { fg = roles.punctuation_dim },
    ["@punctuation.bracket"] = { fg = roles.punctuation },
    ["@punctuation.special"] = { fg = roles.special },

    ["@markup.heading"] = { fg = roles.callable, bold = true },
    ["@markup.link"] = { fg = roles.namespace, underline = true },
    ["@markup.raw"] = { fg = roles.string },
  }

  -- Set both the generic captures and explicit C/C++ variants. The explicit
  -- variants make :Inspect output such as @keyword.type.cpp deterministic.
  set_captures(captures, C_FAMILY)

  -- Captures created by ~/.config/nvim/queries/cpp/highlights.scm.
  set_all({
    ["@punctuation.bracket.round.cpp"] = {
      fg = roles.punctuation,
    },
    ["@punctuation.bracket.curly.cpp"] = {
      fg = roles.punctuation,
    },
    ["@punctuation.bracket.square.cpp"] = {
      fg = roles.punctuation,
    },

    ["@type.alias.cpp"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@type.struct.declaration.cpp"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@type.class.declaration.cpp"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@type.union.declaration.cpp"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@type.enum.declaration.cpp"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },

    ["@type.concept.declaration.cpp"] = {
      fg = roles.concept,
      bold = roles.concept_bold,
    },
  })
end

local function apply_lsp_semantic_tokens(roles)
  local token_types = {
    ["@lsp.type.namespace"] = { fg = roles.namespace },

    ["@lsp.type.type"] = { fg = roles.type },
    ["@lsp.type.class"] = { fg = roles.type },
    ["@lsp.type.struct"] = { fg = roles.type },
    ["@lsp.type.enum"] = { fg = roles.type },
    ["@lsp.type.typeParameter"] = {
      fg = roles.type_parameter,
      italic = roles.type_parameter_italic,
    },
    ["@lsp.type.concept"] = {
      fg = roles.concept,
      bold = roles.concept_bold,
    },

    ["@lsp.type.variable"] = { fg = roles.variable },
    ["@lsp.type.parameter"] = { fg = roles.parameter },
    ["@lsp.type.property"] = { fg = roles.member },

    ["@lsp.type.function"] = { fg = roles.callable },
    ["@lsp.type.method"] = { fg = roles.callable },

    ["@lsp.type.enumMember"] = { fg = roles.constant },
    ["@lsp.type.macro"] = { fg = roles.macro },
    ["@lsp.type.operator"] = { fg = roles.operator },
    ["@lsp.type.bracket"] = { fg = roles.punctuation },
    -- Concepts, variable templates, and similar global compile-time symbols are
    -- sometimes reported by clangd as global-scope variables.
    ["@lsp.typemod.variable.globalScope"] = {
      fg = roles.constant,
    },
  }

  local modifiers = {
    ["@lsp.typemod.variable.readonly"] = { fg = roles.constant },
    ["@lsp.typemod.property.readonly"] = { fg = roles.constant },
    ["@lsp.typemod.variable.static"] = { fg = roles.variable },
    ["@lsp.typemod.property.static"] = { fg = roles.member },

    ["@lsp.typemod.function.constructorOrDestructor"] = {
      fg = roles.callable,
    },
    ["@lsp.typemod.method.constructorOrDestructor"] = {
      fg = roles.callable,
    },

    ["@lsp.typemod.type.defaultLibrary"] = { fg = roles.type },
    ["@lsp.typemod.class.defaultLibrary"] = { fg = roles.type },
    ["@lsp.typemod.function.defaultLibrary"] = { fg = roles.callable },
    ["@lsp.typemod.method.defaultLibrary"] = { fg = roles.callable },

    ["@lsp.typemod.class.declaration"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@lsp.typemod.class.definition"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@lsp.typemod.type.declaration"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
    ["@lsp.typemod.type.definition"] = {
      fg = roles.type,
      bold = roles.declaration_bold,
    },
  }

  set_captures(token_types, C_FAMILY)
  set_captures(modifiers, C_FAMILY)
end

local function apply_legacy_c_cpp(roles)
  set_all({
    cStructure = { fg = roles.keyword },
    cppStructure = { fg = roles.keyword },
    cTypedef = { fg = roles.type },
    cppTypedef = { fg = roles.type },
    cInclude = { fg = roles.preprocessor },
    cppInclude = { fg = roles.preprocessor },
  })
end

function M.apply(mode)
  local palette = require("theme.palette")[mode]

  if not palette then
    error("Unknown theme mode: " .. tostring(mode))
  end

  vim.o.background = mode
  vim.cmd("highlight clear")
  vim.g.colors_name = "dotfiles-" .. mode

  local roles = roles_for(mode, palette)

  apply_ui(palette, roles)
  apply_syntax(roles)
  apply_diagnostics(roles)
  apply_diffs(palette)
  apply_treesitter(roles)
  apply_lsp_semantic_tokens(roles)
  apply_legacy_c_cpp(roles)
end

return M
