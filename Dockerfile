# ============ Etapa 1: compilación ============
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git m4 scons python3 python3-dev python3-pip \
    zlib1g-dev libprotobuf-dev protobuf-compiler libprotoc-dev \
    libgoogle-perftools-dev libhdf5-dev libpng-dev pkg-config \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG GEM5_VERSION=v24.0.0.0
ARG JOBS=12

RUN git clone --depth 1 --branch ${GEM5_VERSION} \
    https://github.com/gem5/gem5.git /opt/gem5
WORKDIR /opt/gem5

# Build ARM + MESI_Two_Level
RUN printf 'BUILD_ISA=y\nUSE_ARM_ISA=y\nRUBY=y\nRUBY_PROTOCOL_MESI_TWO_LEVEL=y\n' > build_opts/ARM_MESI \
    && scons defconfig build/ARM_MESI build_opts/ARM_MESI \
    && grep -E "PROTOCOL" build/ARM_MESI/gem5.build/config \
    && scons build/ARM_MESI/gem5.opt -j${JOBS}

# Build ARM + MOESI_CMP_directory
RUN printf 'BUILD_ISA=y\nUSE_ARM_ISA=y\nRUBY=y\nRUBY_PROTOCOL_MOESI_CMP_DIRECTORY=y\n' > build_opts/ARM_MOESI_CMP_directory \
    && scons defconfig build/ARM_MOESI_CMP_directory build_opts/ARM_MOESI_CMP_directory \
    && grep -E "PROTOCOL" build/ARM_MOESI_CMP_directory/gem5.build/config \
    && scons build/ARM_MOESI_CMP_directory/gem5.opt -j${JOBS}

# libm5 para arm64 (cross-compilado)
RUN cd util/m5 && scons arm64.CROSS_COMPILE=aarch64-linux-gnu- \
    build/arm64/out/m5 -j${JOBS}

# ============ Etapa 2: imagen final ============
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 libpython3.10 libprotobuf23 libgoogle-perftools4 \
    libhdf5-103-1 libhdf5-cpp-103-1 libpng16-16 zlib1g \
    build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    make nano file \
    && rm -rf /var/lib/apt/lists/*

# Binarios, configs de gem5, headers y libm5 (arm64)
COPY --from=builder /opt/gem5/build/ARM_MESI/gem5.opt /opt/gem5/ARM_MESI/gem5.opt
COPY --from=builder /opt/gem5/build/ARM_MOESI_CMP_directory/gem5.opt /opt/gem5/ARM_MOESI_CMP_directory/gem5.opt
COPY --from=builder /opt/gem5/configs /opt/gem5/configs
COPY --from=builder /opt/gem5/include/gem5 /opt/gem5/include/gem5
COPY --from=builder /opt/gem5/util/m5/build/arm64/out/libm5.a /opt/gem5/lib/libm5.a

ENV GEM5_MESI=/opt/gem5/ARM_MESI/gem5.opt \
    GEM5_MOESI=/opt/gem5/ARM_MOESI_CMP_directory/gem5.opt \
    GEM5_CONFIGS=/opt/gem5/configs \
    PYTHONPATH=/opt/gem5/configs \
    M5_INC=/opt/gem5/include \
    M5_LIB=/opt/gem5/lib \
    CC_ARM=aarch64-linux-gnu-gcc

# Archivos del proyecto (después de compilar, para aprovechar la caché)
COPY src/     /gem5_container/src/
COPY configs/ /gem5_container/configs/
COPY scripts/ /gem5_container/scripts/
COPY report/  /gem5_container/report/
COPY results/ /gem5_container/results/

WORKDIR /gem5_container
CMD ["/bin/bash"]