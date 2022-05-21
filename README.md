<p align="center">
  <img src="branding/logo_light.png#gh-light-mode-only">
  <img src="branding/logo_dark.png#gh-dark-mode-only">
</p>

## Intro

Ambry is your personal audiobook shelf. Upload your books to a self hosted
server and stream to any device over the web.

## Running the server

> **NOTE**: This README reflects the `main` branch of this project and is not
> necessarily accurate to the latest stable release.

The easiest way to get up and running quickly is to use the container image
which is hosted on the [GitHub container
registry](https://github.com/features/packages):
<https://github.com/doughsay/ambry/pkgs/container/ambry>

The only external requirement is a [PostgreSQL](https://www.postgresql.org/)
database.

### Compose Example

Here is an example [Docker Compose](https://docs.docker.com/compose/) file that
could be used to run Ambry and the required PostgreSQL database:

```yaml
---
version: "3"
services:
  postgres:
    image: postgres:alpine
    environment:
      - POSTGRES_HOST_AUTH_METHOD=trust
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  ambry:
    image: ghcr.io/doughsay/ambry:latest
    environment:
      - DATABASE_URL=postgres://postgres:postgres@postgres/postgres
      - SECRET_KEY_BASE=FpmsgoGanxtwT6/M9/LbP2vFQP70dVqz2G/lC23lzOo2cmGkl82lW18Q01Av3RGV
      - BASE_URL=http://localhost:9000
      - PORT=9000
    ports:
      - 9000:9000
    volumes:
      - uploads:/app/uploads
    restart: unless-stopped

volumes:
  pgdata:
  uploads:
```

> **WARNING**: The secret key above is only an example, do not use a publicly
> available key!

### Configuration

The following environment variables are used for configuration:

| Variable                    | Description                                                                              | Default | Required? |
| --------------------------- | ---------------------------------------------------------------------------------------- | ------- | --------- |
| `BASE_URL`                  | The url at which you will be serving Ambry. e.g. `https://ambry.mydomain.com`            | N/A     | Yes       |
| `DATABASE_URL`              | A postgresql URL. e.g. `postgresql://username:password@host/database_name`               | N/A     | Yes       |
| `SECRET_KEY_BASE`           | A secret key string of at least 64 bytes, used for signing secrets like session cookies. | N/A     | Yes       |
| `PORT`                      | The port you wish the server to listen on.                                               | `80`    | No        |
| `POOL_SIZE`                 | The number of postgresql database connections to open.                                   | `10`    | No        |
| `USER_REGISTRATION_ENABLED` | Wether or not users are allowed to register themselves with the server.                  | `no`    | No        |

### First Time Setup

The first time Ambry is booted up, it will walk you through setting up your
initial admin user account. Just visit the URL at which you're hosting Ambry to
get started:

-   `http(s)://your-ambry-domain/`

Once that's done, the server will restart and you can log into your new account
and get started using Ambry!

## Local development

Ambry is a [Phoenix](https://phoenixframework.org/)
[LiveView](https://github.com/phoenixframework/phoenix_live_view) application,
so to run the server on your machine for local development follow standard steps
for phoenix applications. To be able to transcode audio files, you'll also need
ffmpeg and shaka-packager available in your path.

### Requirements

-   A [PostgreSQL](https://www.postgresql.org/) server running on localhost (you
    can customize the details in `./config/dev.exs`)
-   [Elixir](https://elixir-lang.org/) and [Erlang/OTP](https://www.erlang.org/)
    installed
-   [Node.js](https://nodejs.org/) LTS (and [Yarn](https://yarnpkg.com/))
    installed
-   [FFmpeg](https://ffmpeg.org/) installed
-   [shaka-packager](https://github.com/google/shaka-packager) installed

For Elixir/Erlang/Nodejs you can easily install all the right versions using
[asdf](https://asdf-vm.com/) by running `asdf install` from within the root
directory. The versions are defined in `.tool-versions`.

```bash
# download hex dependencies
mix deps.get

# download javascript dependencies
( cd assets && yarn )

# create and migrate the database
mix ecto.setup

# run the server
iex -S mix phx.server
```
