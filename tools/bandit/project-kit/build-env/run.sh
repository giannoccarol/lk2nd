#!/usr/bin/env bash
# Esegue un comando (o una shell) nel container di build LineageOS 18.1 del 1520.
# Immagine: los18-build (stessa del cityman A11, Dockerfile qui accanto).
# Container: bandit18-*, albero: ../los18, ccache separata da quella del cityman.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$(cd -- "$here/../los18" && pwd)
mkdir -p "$HOME/.cache/ccache-bandit18"
exec docker run --rm --network host -i $( [ -t 0 ] && echo -t ) \
	-v "$src:/src" -v "$here:/env:ro" -v "$HOME/.cache/ccache-bandit18:/ccache" \
	-v "$HOME/.gitconfig:/home/builder/.gitconfig:ro" \
	-e GIT_COMMITTER_NAME="Lorenzo Giannoccaro" \
	-e GIT_COMMITTER_EMAIL="giannoccarol@users.noreply.github.com" \
	--name "bandit18-$$" los18-build "${@:-bash}"
