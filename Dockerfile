# ---------------------------
# Base Image - elixir-builder
# ---------------------------

# NOTE: make sure these versions match in .tool-versions
# NOTE: make sure the alpine version matches down below
FROM docker.io/hexpm/elixir:1.16.1-erlang-26.2.2-alpine-3.19.1 AS elixir-builder

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

RUN mix release --path /app --quiet



# # --------------------------
# # Base Image - shaka-builder
# # --------------------------
# # Shaka only compiles correctly on alpine 3.12
# FROM docker.io/alpine:3.12 as shaka-builder

# ARG SHAKA_VERSION=7ef51671f1a221443bcd000ccb13189ee6ccf749

# RUN apk --update upgrade && \
#   apk add bash curl bsd-compat-headers linux-headers build-base cmake git ninja python3

# RUN git clone --recurse-submodules https://github.com/shaka-project/shaka-packager.git && \
#   cd shaka-packager && \
#   git checkout $SHAKA_VERSION && \
#   git submodule update --recursive && \
#   cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
#   cmake --build build --parallel



# --------------------------
# Base Image - elixir-runner
# --------------------------
FROM docker.io/alpine:3.19.1 as elixir-runner

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

# COPY --from=shaka-builder --chown=nobody:nogroup /shaka-packager/build/packager/packager /usr/local/bin/shaka-packager
COPY --from=elixir-builder --chown=nobody:nogroup /app /app

RUN mkdir -p /app/uploads
VOLUME /app/uploads

USER nobody

WORKDIR /app
ENTRYPOINT ["/app/bin/ambry"]
CMD ["start"]
