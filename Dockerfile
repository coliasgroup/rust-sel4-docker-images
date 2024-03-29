#syntax=docker/dockerfile:1.4

FROM trustworthysystems/sel4

WORKDIR /tmp

RUN rm -r *

RUN apt-get update -q && apt-get install -y --no-install-recommends \
    # for stack
    libffi-dev \
    libgmp-dev \
    # for qemu
    pkg-config \
    libglib2.0-dev \
    libaio-dev \
    libpixman-1-dev \
    libslirp-dev \
    # for microkit
    python3-venv \
    musl-tools \
    pandoc \
    texlive-latex-base \
    texlive-latex-extra \
    texlive-fonts-recommended \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        bash -s -- -v -y --no-modify-path --default-toolchain none

ENV PATH=/root/.cargo/bin:$PATH

RUN curl -sSL https://get.haskellstack.org/ | bash

RUN set -eux; \
    url="https://developer.arm.com/-/media/Files/downloads/gnu-a/10.2-2020.11/binrel/gcc-arm-10.2-2020.11-x86_64-aarch64-none-elf.tar.xz"; \
    wget -nv "$url"; \
    tar -xf gcc-arm-*.tar.xz; \
    rm gcc-arm-*.tar.xz; \
    mv gcc-arm-* /opt/gcc-aarch64-none-elf;

ENV PATH=/opt/gcc-aarch64-none-elf/bin:$PATH

RUN set -eux; \
    version=7.2.0; \
    url="https://download.qemu.org/qemu-${version}.tar.xz"; \
    wget -nv "$url"; \
    tar -xf qemu-*.tar.xz; \
    rm qemu-*.tar.xz; \
    cd qemu-*; \
    qemu_arm_virt_sp804_url="https://github.com/coliasgroup/qemu/commit/cd3b78de4b5a8d7c79ae99dab2b5e0ab1ba0ffac.patch"; \
    curl -sSL "$qemu_arm_virt_sp804_url" | patch -p1; \
    ./configure \
        --prefix=/opt/qemu \
        --enable-slirp \
        --enable-linux-aio \
        --target-list=arm-softmmu,aarch64-softmmu,riscv32-softmmu,riscv64-softmmu,i386-softmmu,x86_64-softmmu; \
    make -j$(nproc) all; \
    make install; \
    cd ..; \
    rm -rf qemu-*;

ENV PATH=/opt/qemu/bin:$PATH

ENV MICROKIT_SDK_VERSION=1.2.6

# branch: rust
RUN git clone \
        https://github.com/coliasgroup/microkit.git \
        --branch keep/be3c2149f68b17206d9e03e8b038553c \
        --config advice.detachedHead=false

# branch: rust-microkit
RUN git clone \
        https://github.com/coliasgroup/seL4.git \
        --branch keep/fc80c9ad05d33e77a6b850dae8eb4b83 \
        --config advice.detachedHead=false \
        microkit/seL4

RUN set -eux; \
    cd microkit; \
    python3.9 -m venv pyenv; \
    ./pyenv/bin/pip install --upgrade pip setuptools wheel; \
    ./pyenv/bin/pip install -r requirements.txt; \
    ./pyenv/bin/pip install sel4-deps; \
    ./pyenv/bin/python3 build_sdk.py --sel4 ./seL4; \
    chmod a+rX release/microkit-sdk-$MICROKIT_SDK_VERSION/bin/microkit; \
    mkdir /opt/microkit; \
    mv release/microkit-sdk-$MICROKIT_SDK_VERSION /opt/microkit; \
    rm -rf $HOME/.cache/pyoxidizer; \
    cd ..; \
    rm -rf microkit;

ENV MICROKIT_SDK=/opt/microkit/microkit-sdk-$MICROKIT_SDK_VERSION

ENV PATH=$MICROKIT_SDK/bin:$PATH

# branch: coliasgroup
RUN git clone \
        https://github.com/coliasgroup/capdl.git \
        --branch keep/f47bacacb6f5cc81934b6ea3116ef95f \
        --config advice.detachedHead=false

RUN --mount=type=cache,target=/mnt/stack-root,sharing=private \
    set -eux; \
    cd capdl; \
    STACK_ROOT=/mnt/stack-root make -C capDL-tool; \
    install -D -t /opt/capdl/bin capDL-tool/parse-capDL; \
    cp -r python-capdl-tool /opt/capdl; \
    cd ..; \
    rm -rf capdl;

ENV PATH=/opt/capdl/bin:$PATH

# branch: rust
RUN git clone \
        https://github.com/coliasgroup/seL4.git \
        --branch keep/fc80c9ad05d33e77a6b850dae8eb4b83 \
        --config advice.detachedHead=false

RUN --mount=from=src,source=rust-toolchain.toml,target=/mnt/rust-toolchain.toml \
    install -D -t rust-sel4 /mnt/rust-toolchain.toml

RUN --mount=from=src,source=support/targets,target=/mnt/targets \
    install -D -t rust-sel4/targets /mnt/targets/*.json

RUN --mount=source=generate_configs.py,target=generate_configs.py \
    python3 generate_configs.py --out-dir rust-sel4/configs

RUN --mount=source=build_kernels.py,target=build_kernels.py \
    python3 build_kernels.py \
        --tree rust-sel4 \
        --sel4-source seL4 \
        --scratch scratch

RUN rm -rf seL4

RUN --mount=source=Makefile,target=Makefile \
    --mount=from=src,target=/mnt/workspace,readonly \
    --mount=type=cache,target=/mnt/rustup-home,sharing=private \
    --mount=type=cache,target=/mnt/cargo-home,sharing=private \
    --mount=type=cache,target=/mnt/target,sharing=private \
    RUSTUP_HOME=/mnt/rustup-home \
    CARGO_HOME=/mnt/cargo-home \
    make \
        TREE=$(pwd)/rust-sel4 \
        WORKSPACE=/mnt/workspace \
        TARGET_DIR=/mnt/target

RUN mv rust-sel4 /opt

ENV RUST_SEL4_ROOT=/opt/rust-sel4

ENV PATH=${RUST_SEL4_ROOT}/bin:$PATH

WORKDIR /
