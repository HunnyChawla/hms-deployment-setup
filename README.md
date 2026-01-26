# Hospital Management System - Docker Deployment

Production-ready Docker deployment setup for the Hospital Management System (HMS).

## Stack Overview

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| PostgreSQL | hms-postgres | 5444 | Database |
| HMS Backend | hms-backend | 8000 | FastAPI API |
| Hospital UI | hospital-ui | 80 | Next.js Frontend |

## Platform-Specific Setup

Choose your platform for detailed setup instructions:

### Windows
See **[windows/README.md](windows/README.md)** for:
- One-click setup with `hms-setup.bat`
- NSSM auto-start service
- Automated daily backups
- Complete troubleshooting guide

### Linux
Coming soon - see `linux/` folder.

## Quick Configuration

1. Copy `.env.example` to `.env`
2. Edit `.env` and set secure passwords/keys
3. Follow platform-specific instructions above

## Access Points

After deployment:
- **Frontend**: http://localhost
- **Backend API**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs

## Directory Structure

```
hms-deployment-setup/
├── docker-compose.yml    # Docker services configuration
├── .env.example          # Environment template
├── .env                  # Your configuration (create from .env.example)
├── windows/              # Windows deployment scripts
├── linux/                # Linux deployment scripts (coming soon)
├── data/                 # Persistent data (auto-created)
│   ├── postgres/         # Database files
│   ├── uploads/          # User uploads
│   └── logs/             # Application logs
└── backups/              # Database backups
```

## Manual Docker Commands

```bash
# Pull latest images
docker-compose pull

# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# View running containers
docker-compose ps
```
