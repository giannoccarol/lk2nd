# LineageOS 18.1 build environment (Ubuntu 20.04, as in the LineageOS wiki).
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc bison build-essential ca-certificates ccache curl flex g++-multilib \
      gcc-multilib git git-lfs gnupg gperf imagemagick lib32ncurses5-dev \
      lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libncurses5 \
      libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop \
      pngcrush rsync schedtool squashfs-tools xsltproc zip unzip zlib1g-dev \
      python2 python3 python-is-python3 openssh-client procps cpio kmod patchelf \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 755 /usr/local/bin/repo
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID builder && useradd -m -u $UID -g $GID -s /bin/bash builder
USER builder
ENV USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/ccache
WORKDIR /src
