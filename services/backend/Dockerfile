# syntax=docker/dockerfile:1
# Layer order: manifest → resolve deps (cached) → app sources → build (cached).
# Cache mounts persist SwiftPM artifacts across Depot/BuildKit builds (see Depot SSD cache + mount docs).
FROM swift:6.2-jammy AS build
WORKDIR /build

# SwiftPM uses git for dependencies. Git 2.35+ may refuse checkouts under `.build` (dubious ownership)
# when UIDs differ — common with Portainer, rootless builders, or custom build users.
# Non-interactive git avoids hangs if a dependency URL ever misbehaves.
RUN git config --global --add safe.directory '*'
ENV GIT_TERMINAL_PROMPT=0

COPY Package.swift Package.resolved ./

RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/build/.build \
    swift package resolve

COPY Sources ./Sources
COPY Tests ./Tests

# Copy the binary out of the cache mount so it exists in the image layer (mount contents are not saved).
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/build/.build \
    swift build -c release --product App \
    && install -m 0755 /build/.build/release/App /build/App

# Run (Swift runtime + libc compatible with the build)
FROM swift:6.2-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /build/App /app/App
EXPOSE 8080
ENV HOST=0.0.0.0
ENV PORT=8080
# Default bind for Docker / orchestrators; override with `docker run -e PORT=...`
CMD ["/app/App", "serve", "--bind", "0.0.0.0:8080"]
