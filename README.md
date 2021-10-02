# ![ambry](https://raw.githubusercontent.com/doughsay/ambry/main/logo.svg)

> Personal Audiobook Streaming

## Intro

Ambry is your personal audiobook shelf. Upload your books to the server and
stream to any device over the web.

## Running the server

The easiest way currently is to use the provided container images:
<https://github.com/doughsay/ambry/pkgs/container/ambry>

You need to provide a `postgresql` database and configure the image to find it.

### Configuration

You need to provide a few required environment variables to get started:

-   `DATABASE_URL` - A postgresql URL. e.g. `postgresql://username:password@host/database_name`
-   `SECRET_KEY_BASE` - A secret key string of at least 64 bytes.
-   `BASE_URL` - The url at which you will be serving Ambry. e.g. `https://ambry.mydomain.com`
-   `PORT` - The port you wish the server to listen on. e.g. `80`

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
