FROM ghcr.io/gem5/ubuntu-24.04_all-dependencies:v26-0

RUN apt-get update && apt-get install -y --no-install-recommends gcc-aarch64-linux-gnu libc6-dev-arm64-cross && rm -rf /var/lib/apt/lists/*
