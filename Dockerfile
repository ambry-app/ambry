# ---------------------------
# Base Image - elixir-builder
# ---------------------------

# NOTE: make sure these versions match in .tool-versions
# NOTE: make sure the alpine version matches down below
FROM docker.io/hexpm/elixir:1.18.3-erlang-27.3-alpine-3.21.3 AS elixir-builder

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

RUN mix deps.get --only $MIX_ENV && \
  mix deps.compile && \
  mix npm_deps.get

# compile apps

COPY lib/ ./lib
COPY priv/ ./priv

RUN mix compile

# build && deploy assets

COPY assets/ ./assets

RUN mix assets.deploy

# build release

RUN mix sentry.package_source_code
RUN mix release --path /app --quiet



# --------------------------
# Base Image - elixir-runner
# --------------------------
FROM docker.io/alpine:3.21.3 as elixir-runner

ARG SHAKA_PACKAGER_VERSION=3.4.2

RUN apk --update upgrade && \
  apk add openssl ncurses-libs libstdc++ ffmpeg curl

RUN curl -L \
  -o /usr/local/bin/shaka-packager \
  https://github.com/shaka-project/shaka-packager/releases/download/v$SHAKA_PACKAGER_VERSION/packager-linux-x64

RUN chmod +x /usr/local/bin/shaka-packager



# -------------
# Release image
# -------------
FROM elixir-runner AS release-image

ARG APP_REVISION=latest
ARG MIX_ENV=prod

ENV PHX_SERVER=true

COPY --from=elixir-builder --chown=nobody:nogroup /app /app

RUN mkdir -p /app/uploads
VOLUME /app/uploads

USER nobody

WORKDIR /app
ENTRYPOINT ["/app/bin/ambry"]
CMD ["start"]
