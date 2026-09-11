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

### Windows Support

The framework runs under Git Bash from
[Git for Windows](https://gitforwindows.org/). Requirements:

- **Developer Mode** enabled (Settings → System → For developers), so that
  Stow can create symlinks without elevation.
- `bash ./bootstrap.sh` run from a Git Bash window. In PowerShell, `bash`
  is normally WSL's launcher or Git's bare MSYS shell, not Git Bash.

After bootstrap, `dotfiles` is also available from PowerShell and cmd
through `~/.local/bin/dotfiles.cmd`. Missing tools are installed with
`winget`.

## CLI

```
dotfiles list                        List profiles and their status
dotfiles create <name> [desc]        Create a new profile from template
dotfiles remove <name>               Remove a profile from the repository
dotfiles import <name> <path>...     Import existing dotfiles (stow --adopt)

dotfiles status <name>...            Show detailed install status
dotfiles install [--package DIR] [--home DIR] <name>...
                                      prepare + package + stow
dotfiles package [--package DIR] [--home DIR] <name>...
                                      Build a package without stowing it
dotfiles uninstall <name>...         Unstow from the configured home
dotfiles upgrade [--package DIR] [--home DIR] <name>...
                                      Upgrade an installed profile

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
| `package`   | Assemble files in `$DOTFILES_PACKAGE` from source/build artifacts |
| `install`   | Stow `$DOTFILES_PACKAGE` into `$DOTFILES_HOME`           |
| `upgrade`   | Re-run prepare, update plugins, reload configs           |
| `uninstall` | Stop services, then `stow -D ...`                        |

When `DOTFILES_PACKAGE` is set directly or through `--package DIR`, `package`
copies one profile's static files and symlinks there, excluding `.git`, then
renders generated files without running stow. Install and upgrade treat the
selected dotfiles stow package as already assembled. `--home DIR` selects the
stow destination.

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
