# Gold Image Spec — Codespace Base Image

## Background

Current codespace setup takes ~12 minutes per creation. Most of that time is
spent installing tools that every team member needs regardless of project.
This spec defines a "gold image" approach inspired by infrastructures.org:
do the slow shared work once, save it as a Docker image, and start new
codespaces from that image.

## Progressive Image Building

Images are built progressively and cut into new baselines as layers
accumulate. This is the same process used at Chase Manhattan Bank in the
1990s with ISconf, adapted for containers:

1. Start from a vendor-provided base image (e.g. Microsoft's dev container
   Ubuntu image) with a **pinned version number** — never `:latest`.
2. Apply changes through the Makefile in deterministic order. Each step
   drops a stamp file in `/var/deco-make/stamps/` so it is never re-run.
3. When the cumulative install time from a given baseline gets too long
   (e.g. 10–15 minutes), **cut a new baseline image**: snapshot the current
   state, push it to GHCR with a block number tag, and start future builds
   from that new baseline.
4. Update both the Dockerfile `FROM` line **and** `devcontainer.json` image
   reference to point to the new baseline.
5. Continue adding new things to the Makefile on top of this new baseline.
6. Repeat whenever install times creep up again.

This addresses long install times without moving apt installs into the
Dockerfile. The Dockerfile stays minimal (2–3 lines); the Makefile remains
the single source of truth for what gets installed and in what order.
The speed problem is solved by periodically freezing progress into a new
baseline image, not by restructuring where installs happen.

## Block Numbering Scheme

Block numbers track the lineage of baseline images. Each block builds on
the previous one.

| Block | Contents | Based On |
|-------|----------|----------|
| `block_0_0` | Microsoft base image + deco-make binary ONLY. Just enough to be able to do anything else after that. Nothing else is pre-installed. | Vendor image |
| `block_0` | `block_0_0` + base system tools (apt packages, PATH config). The DEFAULT target from workspace-config. | `block_0_0` |
| `block_10` | `block_0` + language runtimes (Go, Python, etc.). | `block_0` |
| `block_12` | `block_10` + additional tools added later. | `block_10` |

The rule: when you cut a new baseline image, you stop adding to the current
block number and start the next one. `block_10` is `block_0` plus more
stuff. `block_12` is `block_10` plus more stuff. The numbering leaves room
for inserting intermediate blocks if needed (e.g. `block_11` between
`block_10` and `block_12`).

When a block is used as a pre-req, the Makefile skips all steps that are
already stamped in the image — they're already done. Only new steps run.

## Naming Cheat Sheet

These names come up across repos and files. Here's what each one is and
where it lives.

| Name | What It Is | Where It Lives |
|------|-----------|----------------|
| **workspace-config** | The shared deco-make configuration — the Makefile and `decomake.conf` that define what gets installed in every codespace regardless of project. This is the "front end" to the Makefile. | `ciwg/workspace-config` repo |
| **workspace-base** | The gold Docker image built from workspace-config. The frozen snapshot that codespaces start from. | `ghcr.io/ciwg/workspace-base` |
| **decomake.conf** | Configuration file that maps project names to their tool sets. Project name string must match the repo name (e.g. `fpga-workbench`). Defines `default` targets (shared) and project-specific targets (e.g. `fpga`). | Inside workspace-config repo |
| **block_0_0** | The very first baseline image. Microsoft base + deco-make only. | Tagged image in GHCR |
| **block_0_0_install** | A Makefile target that installs what's needed for `block_0_0`. If building from a `block_0_0` image, this target is skipped because stamps already exist. | Makefile target |
| **block_0** | The second baseline. `block_0_0` + default tools. | Tagged image in GHCR |
| **block_10, block_12, ...** | Subsequent baselines with progressively more installed. | Tagged images in GHCR |
| **/var/deco-make/stamps/** | Directory where stamp files are created to track completed install steps. Make checks for these to skip already-done work. | Inside the container |
| **/var/deco-make/** | Root directory for deco-make working data. | Inside the container |
| **/var/log/** | Logs from deco-make runs. | Inside the container |

## What goes in the gold image

These are the DEFAULT targets from workspace-config that rarely change and
take the most time to install:

### TOOLS (apt packages)

**All apt packages MUST be version-pinned** (e.g. `neovim=0.9.5-6build1`).
Unversioned `apt-get install` means a rebuild at a later date may produce
a different image. This violates the principle that order matters and that
congruent systems must be fully reproducible from their specification alone.

- vim, neovim, openssh-client
- curl, wget, git, jq, make, python3-pip
- build-essential
- libssl-dev, zlib1g-dev, libbz2-dev, libreadline-dev
- libsqlite3-dev, libffi-dev, liblzma-dev
- PATH configured via /etc/profile.d/

### GO

- Go 1.24.13 installed via goenv
- Set as global default
- **Note:** Boss has a growing belief that we can stop using goenv. Go's
  built-in version management may be sufficient now. To be evaluated.

### PYTHON

- Python 3.12 installed via pyenv
- Set as global default
- **Note:** Consider whether pyenv is needed. Since this is a
  special-purpose container, directly installing the needed Python version
  (or using Python's built-in venv) may be simpler.

## What stays in deco-make (runs at container creation)

Project-specific targets that vary per repo:

- OSS (oss-cad-suite — FPGA only)
- I2C (reference repo clone — FPGA only)
- COCOTB (Python testbench tools — FPGA only)
- Any future project-specific targets

## Where the gold image lives

**Not yet decided.** Current proposal (JJ's recommendation):

    ghcr.io/ciwg/workspace-base

This keeps the image next to the code, uses GitHub org access control,
and is free at our scale — a small team pulling a single image during
codespace creation stays well within ghcr.io free limits. Codespace
pulls via GitHub token do not count against transfer quotas.

Other options still on the table:

1. **GitHub Container Registry (ghcr.io)** — lives next to the code, free
   for public repos, org-level access control (JJ's current recommendation)
2. **Docker Hub** — more widely known, but separate auth
3. **Private registry** — if the team has one

The base image is currently under Computer Sciences but that may not be
the right long-term home. Boss noted he doesn't want the CSWG repo to
become "just images" — it will get messy. Where images live needs to be
discussed as a team.

## Image tagging and versioning

Tags use **block numbers**, not dates. The block number tells you exactly
where in the lineage an image sits.

    ghcr.io/ciwg/workspace-base:block_0_0
    ghcr.io/ciwg/workspace-base:block_0
    ghcr.io/ciwg/workspace-base:block_10

**Never use `:latest`.** Every reference — in devcontainer.json, in the
Dockerfile FROM line — must use a specific block number. If you don't
know what you're getting, you can't prove congruence.

Keep old tagged images around. Never delete them — someone's codespace
may depend on a previous image.

## How it gets built

Manual build until the image contents stabilize.

To build and push a new block:

    docker build -t ghcr.io/ciwg/workspace-base:block_10 .
    docker push ghcr.io/ciwg/workspace-base:block_10

Then update the FROM line in the Dockerfile and the image in
devcontainer.json to point to the new block number.

Long term: GitHub Actions workflow triggered on Makefile changes.
To be decided when image contents stabilize.

## Dockerfile structure

The Dockerfile should be minimal — 2 to 3 lines. All install logic
belongs in the Makefile, not the Dockerfile. The Dockerfile just sets the
base image and kicks off deco-make.

```dockerfile
FROM ghcr.io/ciwg/workspace-base:block_0_0
RUN deco-make run
```

That's it. Everything else — apt installs, tool setup, version pinning,
project-specific configuration — lives in the Makefile where the order is
explicit and visible.

**Why not put installs in the Dockerfile?**

Moving apt installs into the Dockerfile (as Denaldo did to speed up
builds) is valid if Docker is the only tool. But with deco-make in the
picture, having installs in both the Dockerfile and the Makefile creates
confusion about which file owns what. Boss's direction: keep everything
in the Makefile, address speed by cutting new baseline images with block
numbers.

## How devcontainer.json changes

Currently:
```json
"image": "mcr.microsoft.com/devcontainers/base:ubuntu"
```

After gold image:
```json
"image": "ghcr.io/ciwg/workspace-base:block_0_0"
```

The image here **must match** the FROM line in the Dockerfile exactly.
When a new baseline is cut, both must be updated to the same block number.

Everything else stays the same. deco-make still runs via postCreateCommand,
but now it only installs what isn't already in the image. The shared stuff
is already there.

## How deco-make changes

The workspace-config Makefile targets for TOOLS, GO, and PYTHON already
have idempotency checks via stamp files. When the gold image has these
installed, deco-make will see the stamps and skip:

- TOOLS: stamp files exist → nothing installed
- GO: stamp exists → "already installed, skipping"
- PYTHON: stamp exists → "already installed, skipping"

So deco-make still runs DEFAULT, it just finishes in seconds instead of
minutes. If someone creates a codespace without the gold image (or the
image is out of date), deco-make installs everything from scratch as a
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

As the image evolves and more is baked into higher block numbers, even
the project-specific install times may shrink if those tools are included
in a future block.

## Version model — additive, never replace

The team has legacy code. Old Go and Python versions must stay installed
when new ones are added. goenv and pyenv support this natively — multiple
versions live side by side.

Example: the gold image ships with Go 1.24.13. Later the team needs
Go 1.26. Rebuild the image with both:

```dockerfile
# In Makefile (not Dockerfile):
# goenv install 1.24.13   ← stamp exists, skipped
# goenv install 1.26.1    ← new, runs
# goenv global 1.26.1
```

Developers working on legacy code switch locally with `goenv local 1.24.13`
in their project directory. Same pattern for Python.

## Rebuild triggers

Cut a new baseline image (increment the block number) when:
- Cumulative install time from the current baseline gets too long
- A new Go or Python version needs to be ADDED
- New system packages are added to TOOLS
- goenv or pyenv need major updates

NEVER remove a version from the gold image unless the team has confirmed
no code depends on it.

Do NOT rebuild for:
- Project-specific tool changes (cocotb, oss-cad-suite)
- decomake.conf changes
- Makefile changes that only affect project targets

## Open decisions

1. Where should the gold image live? (ghcr.io proposed — not yet decided)
2. Manual or automated builds? (manual to start recommended)
3. Should the gold image repo be ciwg/workspace-base or live inside
   ciwg/workspace-config?
4. What is the deco-make version pin? (@latest needs to be replaced with
   a specific commit or tag)
5. ~~Should apt packages be version-pinned?~~ → **Yes. Pin everything.**
   Boss was explicit: "Pin the versions. Pin everything."
6. Can we drop goenv in favor of Go's built-in version management?
7. Can we drop pyenv in favor of direct Python install or venv?
8. Where should images be stored long-term so the CSWG repo doesn't become
   "just images"?
9. Follow up with Rebecca — boss said this spec "isn't complete especially
   after talking with Rebecca."

## Note on apt version pinning

**Apt packages MUST be version-pinned.** This was an open question in the
previous version of this spec — it is now decided.

Boss's direction: LLMs will tell you "vim has been out so long, we don't
need to pin that." Don't listen. If you don't know exactly what's on the
disk, you don't have congruence — you have convergence at best.

To pin an apt package, use `package=version` syntax:

    apt-get install -y neovim=0.9.5-6build1

To find the current available version:

    apt-cache policy neovim

TODO: Pin all apt packages listed in the TOOLS section above. Get the most
stable version of each, even if it's old.
