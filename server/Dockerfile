FROM dart:3.11.5 AS build
WORKDIR /app
COPY packages/shared packages/shared
COPY server server
COPY database database
WORKDIR /app/server
RUN dart pub get && dart compile exe bin/server.dart -o /app/bin/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/bin/server /app/server
COPY database /app/database
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
