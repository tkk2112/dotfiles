# Agent guidance: dotfiles

## Purpose and boundaries

This repository manages shell, terminal, editor, development tools, local AI services, and host-specific settings with **chezmoi**. Changes should remain reproducible across selected machine profiles and supported operating systems. Prefer editing the declarative source over changing an installed copy or adding an unmanaged installation step.

- `.chezmoiroot` makes `home/` the chezmoi source root. Files at the repository root (including this file, `README.md`, `scripts/`, and `.github/`) are project files, **not** deployed home-directory files.
- Inside `home/`, chezmoi source naming applies: `dot_*` becomes `.*`, `private_*` controls permissions, `executable_*` controls executable mode, and `*.tmpl` is rendered. Source paths and deployed paths are not interchangeable.
- Don't assume macOS configuration applies to Linux or vice versa. Follow profile and OS guards already used by the repository.
- Respect the requested scope. For reviews, assess the supplied changes, distinguishing observed defects from hypotheses. Do not rewrite unrelated configuration.

## Repository map

| Area                             | Primary entry points                                                                                                                                                                         |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Host selection and chezmoi data  | `home/.chezmoi.toml.tmpl`, `home/.chezmoidata/`, `home/.chezmoiignore.tmpl`                                                                                                                  |
| Package catalog and installation | `home/.chezmoidata/packages.yaml`, `home/.chezmoiscripts/`, `setup.sh`                                                                                                                       |
| Shell and command-line workflow  | `home/private_dot_zshrc.tmpl`, `home/dot_zshenv.tmpl`, `home/dot_zsh/`, `home/dot_local/bin/`                                                                                                |
| Terminal and multiplexer         | `home/dot_config/ghostty/`, `home/dot_config/tmux/`                                                                                                                                          |
| Neovim                           | `home/dot_config/nvim/`, especially `lua/config/`                                                                                                                                            |
| LLMs and agents                  | `home/.chezmoidata/llm.yaml`, `home/.chezmoidata/colibri.yaml`, `home/dot_local/bin/executable_dotfiles-llm*`, `home/dot_local/bin/executable_dotfiles-agent.tmpl`, `home/dot_config/goose/` |
| Tests and CI                     | `scripts/test-*.sh`, `.tests/`, `.github/workflows/`, `.pre-commit-config.yaml`                                                                                                              |

Start from these entry points, but discover the **current** implementation before assuming an exact file or function exists.

## Finding and understanding code

1. Check `git status --short` and the relevant diff before editing. Preserve user changes and unrelated work in progress.
1. Search hidden paths and templates. Prefer `rg --files --hidden home scripts` and scoped `rg -n --hidden PATTERN home/...` over repeated, repository-wide `find | grep` pipelines. Exclude downloaded dependencies/test fixtures when they pollute results.
1. A failed search is evidence that the search strategy may be wrong. Inspect directory contents and reconsider filename extensions or source-vs-generated paths; do not repeat an equivalent search indefinitely.
1. Trace behavior end-to-end: data/selection -> template or source implementation -> deployed artifact -> runtime/consumer. Read the functions that implement the behavior, not only filenames or comments.
1. In an answer, identify exact source paths and relevant functions or settings. If the implementation could not be located, state that explicitly rather than inventing an explanation.

## Chezmoi, packages and lifecycle

- Machine profiles and LLM feature/engine/provider selections originate in `home/.chezmoi.toml.tmpl` and the resulting chezmoi configuration. Template data is also supplied by `home/.chezmoidata/*.yaml`.
- Package definitions and groups live in `home/.chezmoidata/packages.yaml`. Installation logic is rendered from files in `home/.chezmoiscripts/`. **Look for `*.sh.tmpl` as well as `*.sh`**; a rendered `.sh` is not necessarily present in the repository.
- `setup.sh` bootstraps installation; do not assume it implements package filtering. Inspect the lifecycle template that consumes package data, including its profile, group, OS, and package-manager predicates.
- `run_once_*`, `run_onchange_*`, and before/after scripts have different execution semantics. Account for reruns, idempotency, and side effects when editing their templates or data dependencies.
- Never edit generated scripts as the source of a permanent fix. Never install a package manually when the task is to manage it through chezmoi.
- Inspect template output with `chezmoi execute-template` as appropriate. Use `chezmoi apply --dry-run --verbose` to review planned changes. An actual `chezmoi apply` can execute install and lifecycle actions; don't run it for a read-only investigation.
- Do not run interactive `chezmoi init --prompt` merely to refresh configuration: it can change selected profiles, features, engines, or providers.

## Shell, Ghostty, tmux and Neovim

- Shell configuration is primarily zsh. Check function/alias definitions and initialization order rather than adding duplicated shortcuts or environment variables.
- Terminal key bindings may cross multiple layers: Ghostty sends escape sequences, tmux may intercept them, and zsh or Neovim consumes them. Test relevant mappings both directly and inside tmux; do not treat a working Ghostty binding as end-to-end proof.
- Neovim configuration is Lua under `home/dot_config/nvim/lua/config/`. Find the plugin and module that own a behavior before changing it. Reuse existing helpers and preserve the project's test conventions.
- Neovim project detection, scopes, subprojects, and out-of-tree project settings are distinct concepts. Trace the existing project registry/settings modules and tests before changing path resolution or persistence. Do not assume project metadata must live inside the source repository.

## AI and agent infrastructure

- `home/.chezmoidata/llm.yaml` declares models and runtimes. Machine-selected features, engines, disabled/manual runtimes, and providers determine what is enabled.
- `dotfiles-llm`, its rendered launcher, and launchd lifecycle scripts together own inference startup and shutdown. Changes to model selection, ports, or endpoints must be checked across all three layers.
- Agent and provider choices are **host-specific**, not repository-wide policy. For example, one Mac may select local inference only (`llmConfig.providers = []`), while a work laptop may enable Codex and Claude. Inspect the current host's chezmoi data and rendered configuration before changing providers, engines, features, or credentials; preserve the selected setup unless asked otherwise.
- Goose is one supported agent front-end; `dotfiles-agent` can connect it to an on-demand local inference runtime on hosts where that runtime is enabled. Do not assume every host runs Goose or local inference. Preserve approval controls and verify **actual tool execution**, not just `/health` or text generation.
- Distinguish a provider **name** from its configured destination: Goose's `openai` provider can point to a localhost OpenAI-compatible server rather than the hosted OpenAI API. Conversely, configured Codex/Claude providers on other hosts may use hosted services. Check the endpoint and machine policy before drawing conclusions about network use.
- Respect the host's privacy and telemetry settings; do not change them or introduce new external data flows without explicit authorization.
- Do not commit downloaded models, runtime state, session databases, credentials, or log files to this repository. Keep persistent session/project knowledge separate from generated runtime caches.

## Verification and reporting

- Choose tests based on the changed subsystem. Available entry points include `scripts/test-profiles.sh`, `scripts/test-llm-config.sh`, `scripts/test-install.sh`, and `scripts/test-nvim.sh`; inspect their prerequisites and side effects before execution. Also consult `.github/workflows/` and `.pre-commit-config.yaml` for CI expectations.
- For templates, validate **rendered output** as well as template syntax (for example, `sh -n` for rendered shell scripts and JSON/YAML validation for rendered configuration).
- For shell changes use relevant lint/format checks; for Neovim changes run the appropriate Lua tests; for LLM changes check generated runtime registration and an end-to-end decision or tool call.
- Check `git diff --check` and review the final diff. Report what was tested, what was not tested, and any remaining uncertainty. Avoid claiming a fix is verified solely because it renders or a service starts.
- Unless explicitly asked to deploy, do not run `chezmoi apply`, restart services, change system settings, install packages, or alter secrets.
