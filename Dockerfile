# ---------------------------
# Base Image - elixir-builder
# ---------------------------

# NOTE: make sure these versions match in .github/workflows/elixir.yml and .tool-versions
# NOTE: make sure the alpine version matches down below
FROM docker.io/hexpm/elixir:1.14.5-erlang-25.3.2-alpine-3.18.0 AS elixir-builder

ARG MIX_ENV=prod

WORKDIR /src

# system updates

RUN mix do \
  local.rebar --force,\
  local.hex --force

RUN apk --update upgrade && \
  apk add build-base git

# fetch deps

COPY config /src/config
COPY mix.exs mix.lock /src/

RUN mix deps.get --only $MIX_ENV
RUN mix npm_deps.get

# compile deps

RUN mix deps.compile

# compile apps

COPY lib/ ./lib
COPY priv/ ./priv

RUN mix compile

# deploy assets

COPY assets/ ./assets

RUN mix assets.deploy

# build release

RUN mix release --path /app --quiet



# --------------------------
# Base Image - elixir-runner
# --------------------------
FROM docker.io/alpine:3.18.0 as elixir-runner

ARG SHAKA_VERSION=2.6.1

RUN apk --update upgrade && \
  apk add openssl ncurses-libs libstdc++ ffmpeg curl

RUN curl -L \
  -o /usr/local/bin/shaka-packager \
  https://github.com/google/shaka-packager/releases/download/v$SHAKA_VERSION/packager-linux-x64

RUN chmod +x /usr/local/bin/shaka-packager



# -------------
# Release image
# -------------
FROM elixir-runner AS release-image

ARG APP_REVISION=latest
ARG MIX_ENV=prod

ENV PHX_SERVER=true

USER nobody

COPY --from=elixir-builder --chown=nobody:nogroup /app /app

RUN mkdir -p /app/uploads
VOLUME /app/uploads

WORKDIR /app
ENTRYPOINT ["/app/bin/ambry"]
CMD ["start"]
