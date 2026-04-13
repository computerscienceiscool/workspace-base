# workspace-base — source for the team's gold image.
#
# Structure mirrors the block model (see gold-server/glossary.md):
#   block00 region = Microsoft base + decomk bootstrap tooling
#   block0  region = decomk runs the workspace-config Makefile
#
# When we cut block00 as its own image, the first region moves upstream
# and this Dockerfile shrinks to ~2 lines.

# ---- block00 region --------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:ubuntu@sha256:4bcb1b466771b1ba1ea110e2a27daea2f6093f9527fb75ee59703ec89b5561cb

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      golang-go=2:1.22~2build1 \
      git=1:2.43.0-1ubuntu7.3 \
      make=4.3-4.1build2 \
      ca-certificates=20240203 \
 && rm -rf /var/lib/apt/lists/*

# TODO: pin decomk to a specific tag/commit once stevegt cuts a stable release.
RUN go install github.com/stevegt/decomk/cmd/decomk@latest \
 && mv /root/go/bin/decomk /usr/local/bin/decomk

# ---- block0 region ---------------------------------------------------------
RUN git clone https://github.com/ciwg/workspace-config /var/decomk/conf \
 && decomk run
