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

`profile.sh` declares `name`, `description`, `supported_os`, `depends`,
`after`, `before`, and defines lifecycle phases:

| Phase       | Purpose                                                  |
|-------------|----------------------------------------------------------|
| `prepare`   | Install upstream packages (brew/apt/pacman/…)            |
| `package`   | Assemble files in `dotfiles/` from `build/` artifacts    |
| `install`   | `stow -d "$PROFILE_ROOT" -t "$HOME" dotfiles`            |
| `upgrade`   | Re-run prepare, update plugins, reload configs           |
| `uninstall` | Stop services, then `stow -D ...`                        |

Each phase is invokable directly: `./profiles/<name>/profile.sh prepare`.

See [profiles/README.md](profiles/README.md) for the full reference.

## Adding a profile

**From scratch** — scaffold from template:
```bash
dotfiles create mynvim "My Neovim setup"
```

**From an external repo** — set `DOTFILES_EXTRA_PROFILES` in `.env` to clone
on bootstrap. Useful for managing secrets in a separate **private** repo
without coupling it to the public dotfiles framework — the URL never lands
in the public repo, and you can fork or change vault providers freely:
```bash
DOTFILES_EXTRA_PROFILES="
    secrets=git@github.com:you/dotfiles-secrets.git
"
```
The cloned repo is treated as a full profile if it contains a framework
`profile.sh` at the root (with `name=` and `supported_os=`); otherwise its
contents are wrapped under `dotfiles/` and a `profile.sh` is auto-generated
from the template.

**Local-only** — drop a profile under `profiles/local/<name>/`. The
directory is gitignored. Lifecycle and `dotfiles list` treat it like any
other profile.

## License

[MIT](LICENSE)
