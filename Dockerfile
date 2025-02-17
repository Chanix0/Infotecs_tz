FROM ubuntu:22.04

# apt setup
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y tzdata
RUN ln -fs /usr/share/zoneinfo/Europe/Moscow /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# Зависимости
RUN apt update && apt install -y \
    build-essential \
    cmake \
    git \
    ccache \
    lcov \
    gcovr \
    pkg-config \
    dh-make \
    dpkg-dev \
    libpcre3-dev \
    zlib1g-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Ccache
ENV CCACHE_DIR=/ccache
RUN mkdir -p $CCACHE_DIR && chmod 777 $CCACHE_DIR
ENV PATH="/usr/lib/ccache:${PATH}"

WORKDIR /build

CMD ["/bin/bash"]
