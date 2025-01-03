FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6 \
    libstdc++6 \
    libubsan1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build flapi /app/flapi
RUN chmod +x /app/flapi

ENTRYPOINT ["/app/flapi"]
