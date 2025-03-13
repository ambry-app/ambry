<p align="center">
  <img src="branding/logo_light.png#gh-light-mode-only">
  <img src="branding/logo_dark.png#gh-dark-mode-only">
</p>

## Intro

Ambry is your personal audiobook library. Upload your books to a self-hosted
server and stream to any device over the web using a browser or a native mobile
app.

This repo holds the code for the Ambry server.

The mobile app code is located here: https://github.com/ambry-app/ambry-mobile-next

## Running the server

> **NOTE**: This README reflects the `main` branch of this project and is not
> necessarily accurate to the latest stable release.

The easiest way to get up and running quickly is to use the container image
which is hosted on the [GitHub container
registry](https://github.com/features/packages):
<https://github.com/doughsay/ambry/pkgs/container/ambry>

The only external requirement is a [PostgreSQL](https://www.postgresql.org/)
database.

You can optionally also supply a headless FireFox instance running marionette
for web-scraping to import metadata from external sources such as GoodReads.

### Compose example

Here is an example [Docker Compose](https://docs.docker.com/compose/) file that
could be used to run Ambry and the required PostgreSQL database:

```yaml
---
version: "3"
services:
  postgres:
    image: postgres:alpine
    container_name: postgres
    environment:
      - POSTGRES_HOST_AUTH_METHOD=trust
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  firefox:
    image: ghcr.io/ambry-app/firefox-headless-marionette:latest
    container_name: firefox
    restart: unless-stopped

  ambry:
    image: ghcr.io/ambry-app/ambry:latest
    container_name: ambry
    environment:
      - DATABASE_URL=postgres://postgres:postgres@postgres/postgres
      - MARIONETTE_URL=tcp://firefox:2828
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

| Variable                    | Description                                                                              | Default          | Required? |
| --------------------------- | ---------------------------------------------------------------------------------------- | ---------------- | --------- |
| `BASE_URL`                  | The url at which you will be serving Ambry. e.g. `https://ambry.mydomain.com`            | N/A              | Yes       |
| `DATABASE_URL`              | A postgresql URL. e.g. `postgresql://username:password@host/database_name`               | N/A              | Yes       |
| `SECRET_KEY_BASE`           | A secret key string of at least 64 bytes, used for signing secrets like session cookies. | N/A              | Yes       |
| `PORT`                      | The port you wish the server to listen on.                                               | `80`             | No        |
| `POOL_SIZE`                 | The number of postgresql database connections to open.                                   | `10`             | No        |
| `USER_REGISTRATION_ENABLED` | Whether or not users are allowed to register themselves with the server.                 | `no`             | No        |
| `MAIL_PROVIDER`             | Valid values: mailjet                                                                    | not-set          | No        |
| `MAIL_FROM_ADDRESS`         | The email address that transactional emails are sent from                                | `noreply@<HOST>` | No        |
| `MARIONETTE_URL`            | A tcp URL to a marionette enabled FireFox. e.g. `tcp://hostname:2828`                    | not-set          | No        |

Based on which mail provider you choose, you will need to supply provider
specific configuration:

#### Mailjet

| Variable          | Description                               |
| ----------------- | ----------------------------------------- |
| `MAILJET_API_KEY` | The API key provided to you by Mailjet    |
| `MAILJET_SECRET`  | The API secret provided to you by Mailjet |

The mail provider is only used for sending registration emails and forgotten
password emails. If you don't need or want this functionality, you can just
leave the `MAIL_PROVIDER` variable unset.

Setting up a fully working email provider requires a domain name that you
control that you can configure correctly with your chosen provider. Currently
the only provider that's working with Ambry is Mailjet, but if there's interest
in others, they can be very easily added.

### First time setup

The first time Ambry is booted up, it will walk you through setting up your
initial admin user account. Just visit the URL at which you're hosting Ambry to
get started:

- `http(s)://your-ambry-domain/`

Once that's done, the server will restart and you can log into your new account
and get started using Ambry!

## Local development

Ambry is a [Phoenix](https://phoenixframework.org/)
[LiveView](https://github.com/phoenixframework/phoenix_live_view) application,
so to run the server on your machine for local development follow standard steps
for phoenix applications. To be able to transcode audio files, you'll also need
ffmpeg and shaka-packager available in your path.

### Requirements

- A [PostgreSQL](https://www.postgresql.org/) server running on localhost (you
  can customize the details in `./config/dev.exs`)
- [Elixir](https://elixir-lang.org/) and [Erlang/OTP](https://www.erlang.org/)
  installed
- [FFmpeg](https://ffmpeg.org/) installed
- [shaka-packager](https://github.com/google/shaka-packager) installed
- (optional) [FireFox](https://www.mozilla.org/firefox) running in headless
  mode with marionette enabled

For Elixir/Erlang you can easily install all the right versions using
[asdf](https://asdf-vm.com/) by running `asdf install` from within the root
directory. The versions are defined in `.tool-versions`.

```bash
# download hex and npm dependencies
mix deps.get
mix npm_deps.get

# create and migrate the database
mix ecto.setup

# run the server
iex -S mix phx.server
```

### Seeds & example files

To add some example books and media to your local database, you can run:

```bash
mix seed
```

This will populate the database with some example books & media, and download &
extract the example books & media files into your local `uploads/` folder.

> **NOTE**: The example files omit the source files for a smaller download-size,
> so visiting the admin audit page (<http://localhost:4000/admin/audit>) will show
> them all as missing their sources.
