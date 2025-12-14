#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Use docker compose v2 if available, otherwise use docker-compose
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

log_info "Starting deployment with Docker Compose..."

# Check if .env file exists
if [ ! -f .env ]; then
    log_error ".env file not found. Please create one before deploying."
    exit 1
fi

log_step "Logging in to GitHub Container Registry..."
# Login to GitHub Container Registry using GITHUB_TOKEN if available
if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
elif [ -f ~/.docker/config.json ]; then
    log_info "Using existing Docker credentials"
else
    log_warn "No GitHub token found. Assuming public image or already logged in."
fi

log_step "Pulling latest images..."
$DOCKER_COMPOSE -f docker-compose.yml pull

log_step "Stopping old containers..."
$DOCKER_COMPOSE -f docker-compose.yml down --remove-orphans

log_step "Running database migrations..."
# Start database first
$DOCKER_COMPOSE -f docker-compose.yml up -d db

# Wait for database to be ready
log_info "Waiting for database to be ready..."
sleep 10

# Run migrations
$DOCKER_COMPOSE -f docker-compose.yml run --rm app /app/bin/social_scribe eval "SocialScribe.Release.migrate"

log_step "Starting all services..."
$DOCKER_COMPOSE -f docker-compose.yml up -d

log_info "Waiting for application to start..."
sleep 15

# Health check
log_step "Running health check..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:4000/health > /dev/null 2>&1; then
        log_info "✅ Health check passed!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log_warn "Health check failed. Retry $RETRY_COUNT/$MAX_RETRIES..."
        sleep 5
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "❌ Health check failed after $MAX_RETRIES attempts!"
    log_error "Showing logs:"
    $DOCKER_COMPOSE -f docker-compose.yml logs app
    exit 1
fi

log_step "Cleaning up old images..."
docker image prune -f

log_info "✅ Deployment completed successfully!"
log_info "Application is running at http://localhost:4000"

# Show running containers
log_info "Running containers:"
$DOCKER_COMPOSE -f docker-compose.yml ps
