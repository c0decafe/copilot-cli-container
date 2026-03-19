# copilot-cli-container

A minimal GitHub Copilot CLI container built with Nix and `devenv`.

There is intentionally no `Dockerfile` here. The image is built directly with `nixpkgs.dockerTools`, which keeps the runtime closure tight, reproducible, and fast to start.

## What is included

- The official `copilot-cli` release binary, pinned by version and hash
- A tiny compiled TTY-aware entrypoint
- CA certificates
- Only the runtime libraries needed by the Copilot binary

The image defaults to:

- `docker run -it ...` -> launch `copilot`
- `docker run ...` -> print a small placeholder/help message and exit `0`
- `docker run ... <command>` -> execute the command directly

## Use the published image

Pull the published image from GHCR:

```bash
docker pull ghcr.io/c0decafe/copilot-cli-container:latest
```

Launch Copilot against the current repository:

```bash
docker run --rm -it \
  --mount type=bind,src="$PWD",target=/workspace \
  -w /workspace \
  ghcr.io/c0decafe/copilot-cli-container:latest
```

Non-interactive placeholder:

```bash
docker run --rm ghcr.io/c0decafe/copilot-cli-container:latest
```

Direct command execution:

```bash
docker run --rm ghcr.io/c0decafe/copilot-cli-container:latest copilot --version
```

## Persist config, auth, and local Copilot state

The image is wired so a single mount point persists the important user state:

- `HOME=/var/lib/copilot`
- `XDG_CONFIG_HOME=/var/lib/copilot/.config`
- `XDG_CACHE_HOME=/var/lib/copilot/.cache`

In practice, mounting `/var/lib/copilot` preserves Copilot's home-directory and XDG-backed files across runs, including things such as `~/.copilot`, cached state, trusted-directory decisions, and other local CLI state.

Recommended: use a named Docker volume for Copilot state, and a bind mount for the repository you want to work in:

```bash
docker volume create copilot-home

docker run --rm -it \
  --mount source=copilot-home,target=/var/lib/copilot \
  --mount type=bind,src="$PWD",target=/workspace \
  -w /workspace \
  ghcr.io/c0decafe/copilot-cli-container:latest
```

If you prefer state on the host filesystem so you can inspect or back it up directly, bind mount a host directory instead:

```bash
mkdir -p "$HOME/.local/share/copilot-cli"

docker run --rm -it \
  --mount type=bind,src="$HOME/.local/share/copilot-cli",target=/var/lib/copilot \
  --mount type=bind,src="$PWD",target=/workspace \
  -w /workspace \
  ghcr.io/c0decafe/copilot-cli-container:latest
```

If you want files written in `/workspace` to match your host UID/GID exactly on systems where your user is not `1000:1000`, add:

```bash
--user "$(id -u):$(id -g)"
```

to the `docker run` examples above.

## Authentication

If you do not provide a token, start the container interactively and run `/login` on first launch. With `/var/lib/copilot` mounted, that local state survives container removal.

If you prefer token-based authentication, pass a GitHub fine-grained PAT with the `Copilot Requests` permission using `GH_TOKEN` or `GITHUB_TOKEN`:

```bash
docker run --rm -it \
  --mount source=copilot-home,target=/var/lib/copilot \
  --mount type=bind,src="$PWD",target=/workspace \
  -w /workspace \
  -e GH_TOKEN \
  ghcr.io/c0decafe/copilot-cli-container:latest
```

`GH_TOKEN` takes precedence when both are set.

## Local development shell

Use `devenv` to get the same pinned `copilot` binary locally:

```bash
devenv shell
```

If you prefer to enter the flake shell directly through Nix, use:

```bash
nix develop --accept-flake-config --no-pure-eval
```

Inside the shell:

- `copilot` runs the local CLI package
- `buildImage` builds the Docker image tarball
- `loadImage` loads `./result` into Docker
- `runImage` runs the image against the current directory

You can also launch the packaged CLI without entering the shell:

```bash
nix run .
```

## Build the image

```bash
nix build .#dockerImage
docker load < result
```

That loads an image named `copilot-cli:latest`.

If you want to use the locally built image instead of GHCR, replace `ghcr.io/c0decafe/copilot-cli-container:latest` with `copilot-cli:latest` in the commands above.

## GitHub publishing

The repository includes `.github/workflows/publish-image.yml`.

On every push to `main`, GitHub Actions builds the same Nix image and publishes it to:

```text
ghcr.io/c0decafe/copilot-cli-container
```

The workflow publishes:

- `ghcr.io/c0decafe/copilot-cli-container:latest`
- `ghcr.io/c0decafe/copilot-cli-container:sha-<full-commit-sha>`
