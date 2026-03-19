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

## Run the image

Interactive default:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  -v copilot-state:/var/lib/copilot \
  copilot-cli:latest
```

Non-interactive placeholder:

```bash
docker run --rm copilot-cli:latest
```

Direct command execution:

```bash
docker run --rm copilot-cli:latest copilot --version
```

## GitHub publishing

The repository includes `.github/workflows/publish-image.yml`.

On every push to `main`, GitHub Actions builds the same Nix image and publishes it to:

```text
ghcr.io/c0decafe/copilot-cli-container
```

The workflow publishes:

- `ghcr.io/c0decafe/copilot-cli-container:latest`
- `ghcr.io/c0decafe/copilot-cli-container:sha-<full-commit-sha>`

## Authentication

On first interactive launch, use the CLI's login flow, or provide one of the supported token environment variables documented by GitHub:

- `COPILOT_GITHUB_TOKEN`
- `GH_TOKEN`
- `GITHUB_TOKEN`

The example `copilot-state` volume keeps CLI state under `/var/lib/copilot`.
