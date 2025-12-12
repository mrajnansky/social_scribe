# Quick Start with Docker

Get Social Scribe running in 3 simple steps!

## 1. Set up environment variables
```bash
cp .env.example .env
```

Edit `.env` and add your API keys (see [DOCKER_SETUP.md](DOCKER_SETUP.md#required-api-keys) for where to get them).

## 2. Start the application
```bash
docker-compose up
```

Wait for the setup to complete (first run takes 2-3 minutes to install dependencies).

## 3. Open your browser
Visit http://localhost:4000

That's it!

## Common Commands

```bash
# Stop the app
docker-compose down

# View logs
docker-compose logs -f app

# Clean restart (removes database)
docker-compose down -v && docker-compose up

# Run migrations
docker-compose exec app mix ecto.migrate

# Access shell
docker-compose exec app bash
```

For detailed setup instructions and troubleshooting, see [DOCKER_SETUP.md](DOCKER_SETUP.md).