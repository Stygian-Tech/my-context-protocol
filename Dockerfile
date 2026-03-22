# Build
FROM swift:6.2-jammy AS build
WORKDIR /build
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
RUN swift build -c release --product App

# Run (Swift runtime + libc compatible with the build)
FROM swift:6.2-jammy
WORKDIR /app
COPY --from=build /build/.build/release/App /app/App
EXPOSE 8080
ENV HOST=0.0.0.0
ENV PORT=8080
# Default bind for Docker / orchestrators; override with `docker run -e PORT=...`
CMD ["/app/App", "serve", "--bind", "0.0.0.0:8080"]
