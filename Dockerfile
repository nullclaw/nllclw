# syntax=docker/dockerfile:1

ARG ZIG_VERSION=0.16.0

FROM --platform=$BUILDPLATFORM debian:stable-slim AS build

ARG TARGETARCH
ARG VERSION=dev
ARG ZIG_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN case "$TARGETARCH" in \
      amd64) zig_arch="x86_64"; zig_target="x86_64-linux-musl" ;; \
      arm64) zig_arch="aarch64"; zig_target="aarch64-linux-musl" ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac \
  && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ --strip-components=1 -C /opt \
  && printf '%s' "$zig_target" > /tmp/zig-target

COPY . .

RUN zig_target="$(cat /tmp/zig-target)" \
  && /opt/zig build -Doptimize=ReleaseSmall -Dtarget="$zig_target" -Dversion="$VERSION"

FROM scratch

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /src/zig-out/bin/nllclw /usr/local/bin/nllclw

ENTRYPOINT ["/usr/local/bin/nllclw"]
