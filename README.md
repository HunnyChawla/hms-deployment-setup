# Hospital Management System - Docker Setup

This docker-compose configuration runs the complete HMS stack:
- **PostgreSQL** - Database (port 5444)
- **HMS Backend** - FastAPI backend (port 8000)
- **Hospital UI** - Next.js frontend (port 80)

## Quick Start

```bash
# Build and start all services
docker-compose up -d --build

# View logs
docker-compose logs -f

# Stop all services
docker-compose down

# Stop and remove volumes (clears database)
docker-compose down -v
```

## Services

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| db | hms-postgres | 5444 | PostgreSQL 15 database |
| hms-backend | hms-backend | 8000 | FastAPI backend API |
| hospital-ui | hospital-ui | 80 | Next.js frontend |

## Configuration

Edit `.env` file to customize settings. See `.env.example` for all options.

## Access

- Frontend: http://localhost
- Backend API: http://localhost:8000
- API Docs: http://localhost:8000/docs
