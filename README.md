# Development Containers Manager

[![CI](https://github.com/marcelfrey29/development-containers-manager/actions/workflows/CI.yml/badge.svg)](https://github.com/marcelfrey29/development-containers-manager/actions/workflows/CI.yml)
[![SAST](https://github.com/marcelfrey29/development-containers-manager/actions/workflows/SAST.yml/badge.svg)](https://github.com/marcelfrey29/development-containers-manager/actions/workflows/SAST.yml)

**Manage Devcontainers from the Terminal: One container per project, IDE-independent, full (Agent) isolation.**

## Installation

`dcm` supports macOS and Linux. To use it, install the following tools:

- A container engine: [Docker](https://www.docker.com/) or [Podman](https://podman.io/)
- [`jq`](https://jqlang.org/)
- [Devcontainer CLI](https://github.com/devcontainers/cli), which requires Node.js: `brew install devcontainer` or `npm install -g @devcontainers/cli`
- [Zed](https://zed.dev/) (v0.232 or newer, with `zed` in your `PATH`) or [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) and `code` in your `PATH` — only needed for `dcm editor`

```bash
curl -fsSL https://raw.githubusercontent.com/marcelfrey29/development-containers-manager/main/install.sh | bash
```

## Usage

Using `dcm` is simple.
If you want to develop inside a Devcontainer with a full IDE/Editor (e.g. Zed or VS Code), simply run `dcm editor` from your project directory.
To start a terminal session (ideal for coding agents) simply run `dcm attach` to launch a login shell in your Devcontainer.

```bash
# Open the project inside the Devcontainer in Zed
dcm editor --name zed

# Launch an Agent Session in OpenCode inside the Devcontainer
dcm exec -- opencode

# Rebuild the Devcontainer, e.g. when the definition changed
dcm recreate
```

| Command                                  | Description                                                                                                                            |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `dcm run [path]`                         | Start the container, creating it if needed. Does nothing if it is already running.                                                     |
| `dcm recreate [path]`                    | Remove the container (`rm`), then start a fresh one (`run`), e.g. after the definition changed.                                        |
| `dcm exec [path] -- <cmd...>`            | Run a command inside the container. Starts it first if needed. `--` is required. Stdin, stdout, stderr and the exit code pass through. |
| `dcm attach [path]`                      | Open an interactive login shell inside the container. Starts it first if needed. Leaving the shell does not stop the container.        |
| `dcm editor [--name=zed\|vscode] [path]` | Open the project in an editor, inside the container. Starts it first if needed. `--name` overrides `editor.name` from the config.      |
| `dcm stop [path]`                        | Stop the container.                                                                                                                    |
| `dcm rm [path]`                          | Stop and delete the container. Volumes and images are kept.                                                                            |
| `dcm --help`                             | Show usage.                                                                                                                            |

`[path]` defaults to the current directory and must contain a devcontainer definition (`.devcontainer/devcontainer.json` or `.devcontainer.json`).

### Configuration

Configuration Location: `~/.devcontainer/dcm-config.json`:

```json
{
    "containerEngine": "docker|podman",
    "dotfiles": { "repo": "<url>", "path": "<target>" },
    "shell": "bash|zsh",
    "editor": { "name": "zed|vscode" }
}
```

| Setting           | Description                                                              | Default                                 |
| ----------------- | ------------------------------------------------------------------------ | --------------------------------------- |
| `containerEngine` | The container engine to use: `docker` or `podman`                        | `docker`                                |
| `dotfiles.repo`   | URL of the dotfiles repository to install.                               | _(none)_                                |
| `dotfiles.path`   | The path in the Devcontainer where the dotfiles repository is installed. | `~/dotfiles` (Devcontainer CLI Default) |
| `shell`           | Shell used when launching an interactive session with `dcm attach`       | `bash`                                  |
| `editor.name`     | Your default editor (e.g. for `dcm editor`): `zed` or `vscode`           | _(none)_                                |

## Development

```bash
# Run SAST Scan locally
trivy fs --scanners vuln,secret,misconfig .
```
