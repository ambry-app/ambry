<p align="center">
  <img width="501" height="112" src="branding/logo_light.png#gh-light-mode-only">
  <img width="501" height="112" src="branding/logo_dark.png#gh-dark-mode-only">
</p>

## Intro

Ambry is your personal audiobook shelf. Upload your books to the server and
stream to any device over the web.

## Running the server

The easiest way currently is to use the provided container images:
<https://github.com/doughsay/ambry/pkgs/container/ambry>

You need to provide a `postgresql` database and configure the image to find it.

### Configuration

You need to provide a few required environment variables to get started:

- `DATABASE_URL` - A postgresql URL. e.g. `postgresql://username:password@host/database_name`
- `SECRET_KEY_BASE` - A secret key string of at least 64 bytes.
- `BASE_URL` - The url at which you will be serving Ambry. e.g. `https://ambry.mydomain.com`
- `PORT` - The port you wish the server to listen on. e.g. `80`

Below is an example `docker-compose.yml` file that could be used to run ambry
and the required postgresql database:

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
    image: ambry:dev
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

## Usage

Once the server is running, you have to first create an account. The account registration link is hidden, so you have to manually type in the address:

- `http(s)://your-ambry-domain/users/register`

Once you have an account you can log in, but it will be empty. To create authors, narrators, books and to upload audio files, you need to visit the admin section and your user account must also be an admin user. Currently, there is no way to create an admin user. The only way to achieve this right now is to manually flip the `admin` boolean on your user account record in the `users` table of the postgres database. Once you are an admin you can visit:

- `http(s)://your-ambry-domain/admin/people`

## Local development

Ambry is a Phoenix LiveView application, so to run the server on your machine for local development follow stanbdard steps for phoenix applications. To be able to transcode audio files, you'll also need ffmpeg and shaka-packager available in your path.

### Requirements

- A `postgresql` server running on localhost (you can customize the details in `./config/dev.exs`)
- Elixir 1.12.x and Erlang/OTP 24.x installed
- Nodejs 16.x installed
- ffmpeg installed
- [shaka-packager](https://github.com/google/shaka-packager) installed

```bash
# download hex dependencies
mix deps.get

# download javascript dependencies
npm install --prefix assets/

# create and migrate the database
mix ecto.setup

# run the server
iex -S mix phx.server
```
