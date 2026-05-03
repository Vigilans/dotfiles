# shell

Shell environment for zsh and bash on linux/macos (pwsh on windows planned). Stows an XDG-style config tree at `~/.config/shell/` and seeds entry rc files (`.zshrc`, `.bashrc`, `.zshenv`, `.profile`, ...) into `$HOME`.

The config tree includes init scripts, interactive-shell rc directories (`.bashrc.d/`, `.zshrc.d/`), aliases, functions, themes, and a layered set of profile dirs (`system/`, `user/`, `local/`) for environment setup. It lives in [Vigilans/shell](https://github.com/Vigilans/shell), pulled in as a submodule at [dotfiles/.config/shell/](dotfiles/.config/shell/).

`prepare` installs base CLI packages and clones zinit (the zsh plugin manager).

`install` copies entry rc files into `$HOME` rather than symlinking, so installer-appended lines (e.g. conda's `conda init`) land in the user copy without bleeding back into source.

## Inputs from other profiles

Other profiles can drop files under `~/.config/shell/{commands,profiles}/local/` to extend the shell environment. The shell profile creates these as real dirs after stow so file-level symlinks from other profiles land cleanly without folding into the wrong source tree.

| Path                    | Loaded as     | When                                          |
| ----------------------- | ------------- | --------------------------------------------- |
| `commands/local/<exec>` | `$PATH` entry | every interactive shell                       |
| `profiles/local/*.sh`   | `source`'d    | login shell, before system/user profile dirs  |
