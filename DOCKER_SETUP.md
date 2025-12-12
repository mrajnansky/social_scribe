# Docker Setup Guide for Social Scribe

This guide will help you get Social Scribe running locally using Docker and Docker Compose.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (version 20.10 or higher)
- [Docker Compose](https://docs.docker.com/compose/install/) (version 2.0 or higher)

## Quick Start

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/mrajnansky/social_scribe.git
   cd social_scribe
   ```

2. **Set Up Environment Variables:**
   ```bash
   cp .env.example .env
   ```

   Edit the `.env` file and add your actual API keys and OAuth credentials:
   ```bash
   nano .env  # or use your preferred editor
   ```

3. **Start the Application:**
   ```bash
   docker-compose up
   ```

   This will:
   - Start a PostgreSQL database container
   - Build and start the Phoenix application container
   - Install all Elixir dependencies
   - Create and migrate the database
   - Start the Phoenix server

4. **Access the Application:**

   Once you see `[info] Running SocialScribeWeb.Endpoint` in the logs, visit:
   - **Application:** http://localhost:4000
   - **Phoenix LiveDashboard:** http://localhost:4000/dev/dashboard

## Docker Commands

### Start the application (detached mode)
```bash
docker-compose up -d
```

### View logs
```bash
docker-compose logs -f app
```

### Stop the application
```bash
docker-compose down
```

### Stop and remove volumes (clean slate)
```bash
docker-compose down -v
```

### Rebuild containers
```bash
docker-compose up --build
```

### Access the app container shell
```bash
docker-compose exec app bash
```

### Run mix commands
```bash
# Run migrations
docker-compose exec app mix ecto.migrate

# Run seeds
docker-compose exec app mix run priv/repo/seeds.exs

# Open IEx console
docker-compose exec app iex -S mix

# Run tests
docker-compose exec app mix test
```

### Database commands
```bash
# Access PostgreSQL
docker-compose exec db psql -U postgres -d social_scribe_dev

# Reset database
docker-compose exec app mix ecto.reset
```

## Configuration

### Environment Variables

All required environment variables are defined in the `.env` file. Here's what you need to configure:

#### Required API Keys

1. **Google OAuth** (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`)
   - Get from: https://console.cloud.google.com/apis/credentials
   - Set authorized redirect URI: `http://localhost:4000/auth/google/callback`

2. **LinkedIn OAuth** (`LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`)
   - Get from: https://www.linkedin.com/developers/apps
   - Set authorized redirect URI: `http://localhost:4000/auth/linkedin/callback`

3. **Facebook OAuth** (`FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`)
   - Get from: https://developers.facebook.com/apps
   - Set authorized redirect URI: `http://localhost:4000/auth/facebook/callback`

4. **Recall.ai** (`RECALL_API_KEY`)
   - Provided by the challenge or get from: https://www.recall.ai/

5. **Google Gemini** (`GEMINI_API_KEY`)
   - Get from: https://aistudio.google.com/app/apikey

### Database Configuration

The Docker setup uses PostgreSQL 16 with the following default credentials:
- **Host:** `db` (container name) or `localhost` (from host machine)
- **Port:** `5432`
- **Username:** `postgres`
- **Password:** `postgres`
- **Database:** `social_scribe_dev`

The database URL is automatically configured in docker-compose.yml.

## Development Workflow

### Hot Reloading

The Docker setup is configured for hot reloading:
- Changes to Elixir files (`.ex`, `.exs`, `.heex`) will automatically recompile
- Changes to assets (CSS, JS) will trigger automatic rebuilds
- The browser will auto-refresh on changes

### Working with Dependencies

When you add new dependencies to `mix.exs`:

```bash
# Restart the container to install new dependencies
docker-compose restart app

# Or rebuild if there are issues
docker-compose up --build
```

### Working with Migrations

```bash
# Create a new migration
docker-compose exec app mix ecto.gen.migration migration_name

# Run pending migrations
docker-compose exec app mix ecto.migrate

# Rollback the last migration
docker-compose exec app mix ecto.rollback
```

## Troubleshooting

### Port 4000 already in use
```bash
# Find and kill the process using port 4000
lsof -ti:4000 | xargs kill -9

# Or change the port in docker-compose.yml
ports:
  - "4001:4000"  # Maps host port 4001 to container port 4000
```

### Port 5432 already in use (PostgreSQL)
If you have PostgreSQL running locally:
```bash
# Stop local PostgreSQL
brew services stop postgresql  # macOS
sudo service postgresql stop   # Linux

# Or change the port in docker-compose.yml
ports:
  - "5433:5432"  # Maps host port 5433 to container port 5432
```

### Database connection errors
```bash
# Recreate the database
docker-compose exec app mix ecto.drop
docker-compose exec app mix ecto.create
docker-compose exec app mix ecto.migrate
```

### Clean slate restart
```bash
# Remove all containers, volumes, and rebuild
docker-compose down -v
docker-compose up --build
```

### Permission issues
```bash
# Fix ownership issues (Linux)
sudo chown -R $USER:$USER .
```

### View detailed logs
```bash
# All services
docker-compose logs -f

# Just the app
docker-compose logs -f app

# Just the database
docker-compose logs -f db
```

## Production Deployment

This Docker setup is optimized for local development. For production deployment:

- Use the existing [Dockerfile](Dockerfile) for building production releases
- Follow the [production deployment guide](README.md#-cicd)
- The project is configured for Fly.io deployment

## Architecture

The Docker Compose setup includes:

1. **PostgreSQL Database** (`db` service)
   - Postgres 16 Alpine image
   - Persistent data volume
   - Health checks enabled

2. **Phoenix Application** (`app` service)
   - Uses official Elixir image (hexpm/elixir:1.17.3)
   - Mounts source code as a volume for hot reloading
   - Automatically installs system dependencies (Node.js, build tools)
   - Automatically installs Elixir and Node.js dependencies
   - Runs database migrations on startup
   - Persistent volumes for deps, _build, and node_modules for faster restarts

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Phoenix Framework Guides](https://hexdocs.pm/phoenix/overview.html)
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Project README](README.md)
