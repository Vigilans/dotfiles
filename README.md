# dotfiles

Profile-based dotfiles, [PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD)-style. Each profile is a self-contained
unit — package install, build steps, and config files — wired into `$HOME`
via [GNU Stow](https://www.gnu.org/software/stow/).

## Install

```bash
git clone https://github.com/Vigilans/dotfiles.git
cd dotfiles
cp .env.example .env       # set DOTFILES_PROFILES=<comma-separated list>
bash ./bootstrap.sh
```

`bootstrap.sh` installs every profile in `DOTFILES_PROFILES` (in dependency
order) and symlinks the `dotfiles` CLI to `~/.local/bin/dotfiles`.

For shell completion:

```bash
eval "$(dotfiles completion zsh)"   # or bash
```

## CLI

```
dotfiles list                        List profiles and their status
dotfiles create <name> [desc]        Create a new profile from template
dotfiles remove <name>               Remove a profile from the repository
dotfiles import <name> <path>...     Import existing dotfiles (stow --adopt)

dotfiles status <name>...            Show detailed install status
dotfiles install <name>...           prepare + package + stow
dotfiles uninstall <name>...         Unstow from $HOME
dotfiles upgrade <name>...           Upgrade an installed profile

dotfiles self update                 Pull latest dotfiles repository
dotfiles self version                Show framework commit SHA, message, and age

dotfiles completion <bash|zsh>       Output completion script
```

## Profiles

```
profiles/<name>/
├── profile.sh          # metadata + lifecycle
├── dotfiles/           # mirrors $HOME — stowed into ~ on install
│   └── .config/<app>/...
└── build/              # local build artifacts (gitignored)
```

`profile.sh` declares `name`, `description`, `supported_os`, `depends`, and
defines lifecycle phases:

| Phase       | Purpose                                                  |
|-------------|----------------------------------------------------------|
| `prepare`   | Install upstream packages (brew/apt/pacman/…)            |
| `package`   | Assemble files in `dotfiles/` from `build/` artifacts    |
| `install`   | `stow -d "$PROFILE_ROOT" -t "$HOME" dotfiles`            |
| `upgrade`   | Re-run prepare, update plugins, reload configs           |
| `uninstall` | Stop services, then `stow -D ...`                        |

Each phase is invokable directly: `./profiles/<name>/profile.sh prepare`.

Stow folds at the directory level, so edits under `profiles/<name>/dotfiles/`
are reflected in `$HOME` immediately. Re-stow only when you add a new
top-level path.

## License

[MIT](LICENSE)
