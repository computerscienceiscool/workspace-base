# Gold Image Spec — Codespace Base Image

## Background

Current codespace setup takes ~12 minutes per creation. Most of that time is
spent installing tools that every team member needs regardless of project.
This spec defines a "gold image" approach inspired by infrastructures.org:
do the slow shared work once, save it as a Docker image, and start new
codespaces from that image.

## What goes in the gold image

These are the DEFAULT targets from workspace-config that rarely change and
take the most time to install:

### TOOLS (apt packages)
- vim, neovim, openssh-client
- curl, wget, git, jq, make, python3-pip
- build-essential
- libssl-dev, zlib1g-dev, libbz2-dev, libreadline-dev
- libsqlite3-dev, libffi-dev, liblzma-dev
- goenv (cloned to /usr/local/goenv)
- pyenv (cloned to /usr/local/pyenv)
- PATH configured via /etc/profile.d/

### GO
- Go 1.24.13 installed via goenv
- Set as global default

### PYTHON
- Python 3.12 installed via pyenv
- Set as global default

## What stays in decomk (runs at container creation)

Project-specific targets that vary per repo:

- OSS (oss-cad-suite — FPGA only)
- I2C (reference repo clone — FPGA only)
- COCOTB (Python testbench tools — FPGA only)
- Any future project-specific targets

## Where the gold image lives

The gold image will be hosted at:

    ghcr.io/ciwg/workspace-base

This keeps the image next to the code, uses GitHub org access control,
and is free at our scale — a small team pulling a single image during
codespace creation stays well within ghcr.io free limits. Codespace
pulls via GitHub token do not count against transfer quotas.

This is a temporary decision. Long term options for team to decide:

1. **GitHub Container Registry (ghcr.io)** — lives next to the code, free for
   public repos, org-level access control
2. **Docker Hub** — more widely known, but separate auth
3. **Private registry** — if the team has one


## Image tagging and versioning

Tags should encode what's inside. As versions accumulate, use a build
date or sequence number rather than listing every version:

- `ghcr.io/ciwg/workspace-base:2026-04-07` (date-based)
- `ghcr.io/ciwg/workspace-base:latest` (points to current)

Keep old tagged images around. Never delete them — someone's codespace
may depend on a previous image.

## How it gets built

Manual build until the image contents stabilize.

To build and push:

    docker build -t ghcr.io/ciwg/workspace-base:$(date +%Y-%m-%d) .
    docker push ghcr.io/ciwg/workspace-base:$(date +%Y-%m-%d)
    docker tag ghcr.io/ciwg/workspace-base:$(date +%Y-%m-%d) ghcr.io/ciwg/workspace-base:latest
    docker push ghcr.io/ciwg/workspace-base:latest

Long term: GitHub Actions workflow triggered on Dockerfile changes.
To be decided when image contents stabilize.

## Dockerfile structure

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# System packages (not version-pinned — see workspace-config Makefile note)
RUN apt-get update -qq && apt-get install -y -qq \
    vim neovim openssh-client \
    curl wget git jq make python3-pip \
    build-essential \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libffi-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# goenv
RUN git clone https://github.com/go-nv/goenv.git /usr/local/goenv
ENV GOENV_ROOT="/usr/local/goenv"
ENV PATH="$GOENV_ROOT/bin:$GOENV_ROOT/shims:$PATH"

# Go versions — add new versions here, never remove old ones
RUN goenv install 1.24.13
RUN goenv global 1.24.13

# pyenv
RUN git clone https://github.com/pyenv/pyenv.git /usr/local/pyenv
ENV PYENV_ROOT="/usr/local/pyenv"
ENV PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

# Python versions — add new versions here, never remove old ones
RUN pyenv install 3.12
RUN pyenv global 3.12

# PATH setup for login shells
RUN echo 'export GOENV_ROOT="/usr/local/goenv"' > /etc/profile.d/goenv.sh && \
    echo 'export PATH="$GOENV_ROOT/bin:$GOENV_ROOT/shims:$PATH"' >> /etc/profile.d/goenv.sh
RUN echo 'export PYENV_ROOT="/usr/local/pyenv"' > /etc/profile.d/pyenv.sh && \
    echo 'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"' >> /etc/profile.d/pyenv.sh
```

## How devcontainer.json changes

Currently:
```json
"image": "mcr.microsoft.com/devcontainers/base:ubuntu"
```

After gold image:
```json
"image": "ghcr.io/ciwg/workspace-base:2026-04-07"
```

Everything else stays the same. decomk still runs via postCreateCommand,
but now it only installs project-specific tools. The shared stuff is
already in the image.

## How decomk changes

The workspace-config Makefile targets for TOOLS, GO, and PYTHON already
have idempotency checks. When the gold image has these installed, decomk
will see them and skip:

- TOOLS: apt packages already present → stamps created, nothing installed
- GO: goenv sees 1.24.13 → "already installed, skipping"
- PYTHON: pyenv sees 3.12 → "already installed, skipping"

So decomk still runs DEFAULT, it just finishes in seconds instead of
minutes. If someone creates a codespace without the gold image (or the
image is out of date), decomk installs everything from scratch as a
fallback. The gold image is a speed optimization, not a hard dependency.

## Expected time savings

| Step | Without gold image | With gold image |
|------|-------------------|-----------------|
| TOOLS (apt) | ~2 min | skipped |
| GO (goenv + compile) | ~3 min | skipped |
| PYTHON (pyenv + compile) | ~4 min | skipped |
| OSS (1.3GB download) | ~3 min | ~3 min |
| I2C + COCOTB | ~30 sec | ~30 sec |
| **Total** | **~12 min** | **~4 min** |

## Version model — additive, never replace

The team has legacy code. Old Go and Python versions must stay installed
when new ones are added. goenv and pyenv support this natively — multiple
versions live side by side.

Example: the gold image ships with Go 1.24.13. Later the team needs
Go 1.26. Rebuild the image with both:

```dockerfile
RUN goenv install 1.24.13
RUN goenv install 1.26.1
RUN goenv global 1.26.1
```

Developers working on legacy code switch locally with `goenv local 1.24.13`
in their project directory. Same pattern for Python.

## Rebuild triggers

Rebuild the gold image when:
- A new Go or Python version needs to be ADDED
- New system packages are added to TOOLS
- goenv or pyenv need major updates

NEVER remove a version from the gold image unless the team has confirmed
no code depends on it.

Do NOT rebuild for:
- Project-specific tool changes (cocotb, oss-cad-suite)
- decomk.conf changes
- Makefile changes that only affect project targets

## Open decisions  

1. Where should the gold image live? (ghcr.io recommended): Temporarily addressed.
2. Manual or automated builds? (manual to start recommended)
3. Should the gold image repo be ciwg/workspace-base or live inside
   ciwg/workspace-config?
4. What is the decomk version pin? (@latest needs to be replaced with
   a specific commit or tag)
5. Should apt packages be version-pinned for full reproducibility, or
   is the current approach (latest from apt, pinned for Go/Python/cocotb)
   acceptable?


## Note on apt version pinning

System packages installed via apt-get are NOT version-pinned. apt-get
update pulls the latest package list, so versions may differ depending
on when the image is built. This affects: vim, neovim, openssh-client,
curl, wget, git, jq, make, python3-pip, build-essential, and all
pyenv/goenv build dependencies.

Pinned tools (Go, Python, cocotb, oss-cad-suite) are not affected by
this. They use their own install mechanisms with explicit version numbers.

TODO: pin apt packages to specific versions for full reproducibility.
Unversioned apt installs mean a Dockerfile rebuild at a later date may
produce a different image. Mitigated for now by never deleting tagged
images — a tagged image is frozen at build time. However, this violates
the infrastructures.org recovery principle: we cannot guarantee an
identical rebuild from the Dockerfile alone. Raise with team before
the first production build.
