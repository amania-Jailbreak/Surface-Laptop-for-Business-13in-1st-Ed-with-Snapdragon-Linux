FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bc \
        binutils-aarch64-linux-gnu \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        device-tree-compiler \
        file \
        flex \
        gcc-aarch64-linux-gnu \
        gzip \
        libelf-dev \
        libssl-dev \
        python3 \
        ripgrep \
        systemd-ukify \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENTRYPOINT ["./build.sh"]
CMD ["check"]
