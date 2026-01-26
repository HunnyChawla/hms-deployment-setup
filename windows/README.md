# HMS Docker Deployment - Windows Guide

Complete guide for deploying and managing the Hospital Management System on Windows.

## Stack Overview

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| PostgreSQL | hms-postgres | 5444 | Database |
| HMS Backend | hms-backend | 8000 | FastAPI API |
| Hospital UI | hospital-ui | 80 | Next.js Frontend |

## Prerequisites

### Required Software

1. **Docker Desktop for Windows**
   - Download: https://www.docker.com/products/docker-desktop
   - Enable WSL2 backend (recommended)
   - Ensure Docker is running before deployment

2. **PowerShell 5.1+**
   - Included with Windows 10/11
   - Check version: `$PSVersionTable.PSVersion`

**Note:** NSSM (for auto-start service) is bundled in `windows/dependencies/nssm/` - no separate installation required.

## Quick Start

### Step 1: Configure Environment

```powershell
# Navigate to project root
cd path\to\hms-deployment-setup

# Create your .env file from template
Copy-Item .env.example .env

# Edit .env with your settings
notepad .env
```

**Important:** Update these security-critical values in `.env`:
```bash
POSTGRES_PASSWORD=your-secure-password
JWT_SECRET_KEY=random-string-minimum-32-characters
LICENSE_ENCRYPTION_KEY=another-random-string-32-chars
```

### Step 2: Run Setup

**Double-click `windows\hms-setup.bat`** to open the setup menu.

For first-time setup, select **[1] Full Setup** which will:
- Initialize data directories
- Pull Docker images
- Start all services
- Optionally install auto-start service
- Optionally configure daily backups

### Step 3: Access Application

After deployment:
- **Frontend**: http://localhost (or configured FRONTEND_PORT)
- **Backend API**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs

## Orchestrator Menu

The `hms-setup.bat` file opens an interactive menu:

```
========================================
  HMS Docker Deployment - Windows Setup
========================================

Select an option:

  [1] Full Setup (First Time)
  [2] Deploy/Update Services
  [3] Backup Database Now
  [4] Restore Database
  [5] Docker Cleanup
  [6] Service Management (NSSM)
  [7] View Status & Logs
  [0] Exit
```

## Configuration Reference

### Environment Variables

All configuration is done via the `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| **Image Versions** |||
| `POSTGRES_VERSION` | `15-alpine` | PostgreSQL image tag |
| `BACKEND_IMAGE_TAG` | `latest` | Backend image version |
| `FRONTEND_IMAGE_TAG` | `latest` | Frontend image version |
| **Ports** |||
| `POSTGRES_PORT` | `5444` | Database port |
| `APP_PORT` | `8000` | Backend API port |
| `FRONTEND_PORT` | `80` | Frontend port |
| **Database** |||
| `POSTGRES_USER` | `postgres` | Database username |
| `POSTGRES_PASSWORD` | (required) | Database password |
| `POSTGRES_DB` | `hms_db` | Database name |
| **Security** |||
| `JWT_SECRET_KEY` | (required) | JWT signing key (32+ chars) |
| `LICENSE_ENCRYPTION_KEY` | (required) | Encryption key (32+ chars) |
| **Backup** |||
| `BACKUP_RETENTION_DAYS` | `30` | Days to keep backups |

### Version Pinning

For production, pin specific versions:

```bash
POSTGRES_VERSION=15.4-alpine
BACKEND_IMAGE_TAG=v1.2.3
FRONTEND_IMAGE_TAG=v1.2.3
```

## Manual Script Usage

For advanced users, scripts can be run directly:

### Deploy Services
```powershell
.\windows\scripts\deploy.ps1              # Standard deploy
.\windows\scripts\deploy.ps1 -NoPull      # Skip pulling new images
.\windows\scripts\deploy.ps1 -Force       # Force recreate containers
```

### Docker Cleanup
```powershell
.\windows\scripts\cleanup.ps1 -Level minimal    # Stopped containers + dangling images
.\windows\scripts\cleanup.ps1 -Level standard   # + unused networks
.\windows\scripts\cleanup.ps1 -Level aggressive # Full cleanup (with confirmation)
.\windows\scripts\cleanup.ps1 -DryRun           # Preview only
```

### Database Backup
```powershell
.\windows\scripts\backup-database.ps1                    # Create backup
.\windows\scripts\backup-database.ps1 -RetentionDays 14  # Custom retention
```

### Database Restore
```powershell
.\windows\scripts\restore-database.ps1                            # Interactive
.\windows\scripts\restore-database.ps1 -BackupFile "path\to.sql"  # Specific file
```

### NSSM Service Management
```powershell
# Requires Administrator privileges
.\windows\scripts\install-service.ps1 -Action install   # Install service
.\windows\scripts\install-service.ps1 -Action start     # Start service
.\windows\scripts\install-service.ps1 -Action stop      # Stop service
.\windows\scripts\install-service.ps1 -Action status    # Check status
.\windows\scripts\install-service.ps1 -Action remove    # Remove service
```

### Scheduled Backups
```powershell
# Requires Administrator privileges
.\windows\scripts\setup-backup-schedule.ps1              # Setup 2 AM daily backup
.\windows\scripts\setup-backup-schedule.ps1 -Time "03:00" # Custom time
.\windows\scripts\setup-backup-schedule.ps1 -Remove      # Remove schedule
```

## Directory Structure

```
hms-deployment-setup/
├── docker-compose.yml      # Docker services definition
├── .env                    # Your configuration (create from .env.example)
├── .env.example            # Configuration template
├── windows/                # Windows scripts
│   ├── hms-setup.bat       # Double-click entry point
│   ├── orchestrator.ps1    # Main menu
│   ├── README.md           # This file
│   ├── scripts/            # PowerShell scripts
│   └── dependencies/       # Bundled tools
│       └── nssm/           # NSSM for Windows services
├── data/                   # Persistent data (auto-created)
│   ├── postgres/           # Database files
│   ├── uploads/            # User uploads
│   └── logs/               # Application logs
└── backups/                # Database backups
```

## Auto-Start on Windows Boot

### Option 1: NSSM Service (Recommended)

1. Run `hms-setup.bat` as Administrator
2. Select **[6] Service Management**
3. Select **[1] Install Service**
4. Select **[2] Start Service**

The service will:
- Start automatically on Windows boot
- Restart HMS containers (without pulling new images)
- Log output to `data\logs\service-*.log`

### Option 2: Task Scheduler (Manual)

1. Open Task Scheduler (`taskschd.msc`)
2. Create Basic Task
3. Trigger: "When the computer starts"
4. Action: Start a program
5. Program: `powershell.exe`
6. Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\windows\scripts\deploy.ps1" -NoPull`

## Backup and Restore

### Automated Daily Backups

1. Run `hms-setup.bat` as Administrator
2. Select **[1] Full Setup** and answer 'y' to backup setup
   OR select **[6] Service Management** then setup backup schedule

Backups are stored in `backups/` with format: `hms_backup_YYYY-MM-DD_HH-mm-ss.sql`

### Manual Backup

1. Run `hms-setup.bat`
2. Select **[3] Backup Database Now**

### Restore from Backup

1. Run `hms-setup.bat`
2. Select **[4] Restore Database**
3. Select backup from list
4. Type `RESTORE` to confirm

**Warning:** Restore will DELETE all existing data!

### Backup Retention

Old backups are automatically deleted based on `BACKUP_RETENTION_DAYS` in `.env` (default: 30 days).

## Docker Cleanup Strategy

Docker can consume excessive disk space. Use cleanup options:

| Level | What it removes | When to use |
|-------|-----------------|-------------|
| Minimal | Stopped containers, dangling images | Regular maintenance |
| Standard | + Unused networks | Weekly cleanup |
| Aggressive | + All unused images, build cache | When low on disk |

**Safe to remove:**
- Stopped containers
- Dangling/unused images
- Unused networks
- Build cache

**Never removed by cleanup:**
- Running containers
- `data/` directory (database, uploads, logs)
- `backups/` directory

## Troubleshooting

### Docker Desktop Not Running

```
Error: Docker is not running
```

**Solution:** Start Docker Desktop from the Start menu and wait for it to fully load (whale icon in system tray stops animating).

### Port Already in Use

```
Error: Bind for 0.0.0.0:80 failed: port is already allocated
```

**Solution:** Change the port in `.env`:
```bash
FRONTEND_PORT=8080
```

### Container Won't Start

Check container logs:
```powershell
docker logs hms-postgres
docker logs hms-backend
docker logs hospital-ui
```

### Database Connection Failed

1. Ensure PostgreSQL container is healthy:
   ```powershell
   docker ps
   docker logs hms-postgres
   ```

2. Check DATABASE_URL matches your `.env` settings

### Permission Denied on Data Directory

Run as Administrator:
```powershell
icacls ".\data" /grant Everyone:F /T
```

### NSSM Not Found

NSSM is bundled with this project. If you see this error:

1. Verify the file exists: `windows\dependencies\nssm\nssm.exe`
2. If missing, re-clone the repository or download NSSM from https://nssm.cc/download
3. Place `nssm.exe` in `windows\dependencies\nssm\`

### Clean Restart

If all else fails:

```powershell
# Stop all containers
docker-compose down

# Remove data (WARNING: deletes database!)
Remove-Item -Recurse -Force .\data

# Reinitialize and deploy
.\windows\hms-setup.bat
# Select [1] Full Setup
```

## Production Best Practices

1. **Security**
   - Always change default passwords in `.env`
   - Use 32+ character random strings for JWT_SECRET_KEY and LICENSE_ENCRYPTION_KEY
   - Keep `.env` file secure and never commit to git

2. **Backups**
   - Enable automated daily backups
   - Periodically verify backups by testing restore
   - Consider off-site backup storage

3. **Version Pinning**
   - Pin specific image versions in production
   - Test updates in staging before production

4. **Monitoring**
   - Check container status regularly
   - Monitor disk space usage
   - Review logs for errors

5. **Updates**
   - Pull latest images: `docker-compose pull`
   - Restart services: use Deploy option in menu
   - Always backup before updating

## Support

For issues:
1. Check this troubleshooting guide
2. View container logs
3. Check Docker Desktop logs
4. Report issues at project repository
