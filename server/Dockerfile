# Fish Game dedicated server for Edgegap. Build from the repository root:
#   docker build --platform linux/amd64 -f server/Dockerfile -t fishgame-server:<tag> .
ARG GODOT_VERSION=4.7.2

FROM ubuntu:22.04 AS godot
ARG GODOT_VERSION
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /godot
RUN curl -fsSLO "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" && \
    curl -fsSLO "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/SHA512-SUMS.txt" && \
    grep "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" SHA512-SUMS.txt | sha512sum -c - && \
    unzip -q "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" && \
    mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" godot && chmod +x godot && \
    rm -f *.zip SHA512-SUMS.txt

# Export the game with the "Linux Server" preset (dedicated server: no textures
# or sounds). A .pck needs no export templates.
FROM godot AS export
WORKDIR /project
COPY . .
RUN mkdir -p build/server && \
    /godot/godot --headless --path . --import && \
    /godot/godot --headless --path . --export-pack "Linux Server" build/server/fishgame-server.pck && \
    test -s build/server/fishgame-server.pck

FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 server
WORKDIR /app
COPY --from=godot /godot/godot /app/godot
COPY --from=export /project/build/server/fishgame-server.pck /app/fishgame-server.pck
USER server

# Documentation only: the port Edgegap exposes is the one on the app version.
EXPOSE 7777/udp

CMD ["/app/godot", "--headless", "--main-pack", "/app/fishgame-server.pck", "--", "--server", "--port=7777"]
