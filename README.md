# workspace-base

Source repo for the team's gold image. This repo's Dockerfile builds the
baseline devcontainer image that project repos pull from.

The concept comes from the infrastructures.org gold server model:
http://www.infrastructures.org/bootstrap/gold.shtml — do the slow shared
work once, save it, and let every machine grow from that known-good state.

See `gold-server/glossary.md` for terms and the block-numbering scheme.
See `gold-server/gold-image-spec.md` for the full spec.

## What's in the image

Built by a minimal Dockerfile that invokes decomk. decomk reads the
workspace-config Makefile and runs the TOOLS + GO + PYTHON targets at
image build time. What ends up in the image:

- Base: `mcr.microsoft.com/devcontainers/base:ubuntu`, pinned by sha256.
- Bootstrap layer: `golang-go`, `git`, `make`, `ca-certificates`, `decomk`.
- Shared tools from workspace-config/Makefile TOOLS target: vim, neovim,
  openssh-client, curl, wget, git, jq, make, python3-pip, build-essential,
  libssl-dev, zlib1g-dev, libbz2-dev, libreadline-dev, libsqlite3-dev,
  libffi-dev, liblzma-dev — all pinned to their Ubuntu 24.04 (noble)
  versions.
- goenv with Go 1.24.13 installed and set as global default.
- pyenv with Python 3.12 installed and set as global default.

Project-specific tools (oss-cad-suite, cocotb, etc.) are **not** in the
image — decomk installs them at container-create time based on which
project repo is opening the container.

## How to use it in a devcontainer

Once the image is built and hosted, set in your repo's
`.devcontainer/devcontainer.json`:

    "image": "ghcr.io/ciwg/workspace-base:blockN"

(GHCR hosting is out of scope for now; Steve will decide where images
live. Until then, the image is built locally and not pushed.)

## Block numbering

- `block00` = Microsoft base + decomk only (this Dockerfile's upper region)
- `block0`  = `block00` + TOOLS + GO + PYTHON (what this Dockerfile produces)
- `block10` = `block0` + the next shared layer, when install time grows

See `gold-server/glossary.md` for the full scheme.

## Building locally

    docker build -t workspace-base:block0-$(date +%Y-%m-%d) .

Nothing is pushed. Never delete old tags — someone's codespace may depend
on a previous image.

## When to rebuild

- New shared package added to workspace-config/Makefile TOOLS, GO, or PYTHON
- Base image needs to be re-pinned (security patches, etc.)
- Adding a new Go or Python version (additive only — never remove old ones)

Do not rebuild for project-specific tool changes. Those live in the
workspace-config Makefile and are applied by decomk at container-create
time.

## Pinning policy

Every `apt install` version is pinned to the Ubuntu 24.04 noble version
current as of the base image's sha256. When the base image digest is
updated, the version strings in the Makefile must be re-queried and
updated together. Unpinned apt installs are not permitted.
