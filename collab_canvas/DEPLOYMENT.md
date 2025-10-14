# Fly.io Deployment Guide

## Overview
This Phoenix LiveView application is configured for deployment on Fly.io with SQLite database storage on a persistent volume.

## Configuration Files Created

- **fly.toml**: Main Fly.io configuration with volume mount
- **Dockerfile**: Multi-stage build optimized for Phoenix
- **.dockerignore**: Excludes unnecessary files from Docker context
- **rel/env.sh.eex**: Distributed Elixir configuration
- **bin/server**: Server startup script

## Database Configuration

### Development
- Uses local SQLite: `config/collab_canvas_dev.db`
- Can override with `DATABASE_PATH` environment variable

### Production
- Uses persistent volume mounted at `/data`
- Database path: `/data/collab_canvas.db`
- Configured via `DATABASE_PATH` environment variable

## Required Environment Variables

### Set these secrets on Fly.io:

```bash
# Generate a secret key base
mix phx.gen.secret

# Set secrets
fly secrets set SECRET_KEY_BASE="<generated-secret>" -a ph-beam
fly secrets set AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com" -a ph-beam
fly secrets set AUTH0_CLIENT_ID="<your-client-id>" -a ph-beam
fly secrets set AUTH0_CLIENT_SECRET="<your-client-secret>" -a ph-beam
fly secrets set CLAUDE_API_KEY="<your-claude-key>" -a ph-beam
```

### Already configured in fly.toml:
- `DATABASE_PATH=/data/collab_canvas.db`
- `PHX_HOST=ph-beam.fly.dev`
- `PORT=8080`
- `ECTO_IPV6=true`
- `ERL_AFLAGS=-proto_dist inet6_tcp`

## Deployment Steps

### 1. Build and deploy assets
```bash
mix assets.deploy
```

### 2. Deploy to Fly.io
```bash
fly deploy
```

### 3. Run database migrations
```bash
fly ssh console -a ph-beam
cd /app && /app/bin/collab_canvas eval "CollabCanvas.Release.migrate"
```

Or create a rel/overlays/bin/migrate script:
```bash
#!/bin/sh
set -eu

cd -P -- "$(dirname -- "$0")"
exec ./collab_canvas eval CollabCanvas.Release.migrate
```

### 4. Check application status
```bash
fly status -a ph-beam
fly logs -a ph-beam
```

### 5. Open your application
```bash
fly apps open -a ph-beam
```

## Update Auth0 Configuration

Add your production URL to Auth0:
1. Go to Auth0 Dashboard → Applications → Your App
2. Add to Allowed Callback URLs:
   - `https://ph-beam.fly.dev/auth/auth0/callback`
3. Add to Allowed Logout URLs:
   - `https://ph-beam.fly.dev/`
4. Add to Allowed Web Origins:
   - `https://ph-beam.fly.dev`

## Volume Management

Your volume "ph" is already created in the ord region.

### View volume
```bash
fly volumes list -a ph-beam
```

### Create snapshot (backup)
```bash
fly volumes snapshots create <volume-id> -a ph-beam
```

### Restore from snapshot
```bash
fly volumes create ph_backup --snapshot-id <snapshot-id> --region ord -a ph-beam
```

## Troubleshooting

### Check logs
```bash
fly logs -a ph-beam
```

### SSH into the machine
```bash
fly ssh console -a ph-beam
```

### Check database file
```bash
fly ssh console -a ph-beam
ls -lah /data/
```

### Check environment variables
```bash
fly ssh console -a ph-beam
printenv | grep -E "(DATABASE_PATH|PHX_HOST|AUTH0)"
```

### Scale machines
```bash
# Scale to 2 machines
fly scale count 2 -a ph-beam

# Scale back to 1
fly scale count 1 -a ph-beam
```

## Health Checks

The application includes a health check endpoint at `/health`. Configure it in your Phoenix router if not already present:

```elixir
scope "/", CollabCanvasWeb do
  pipe_through :browser

  get "/health", HealthController, :index
end
```

## Performance Considerations

- **Auto-start/stop**: Configured to stop when idle, starts on request
- **Memory**: 1GB allocated (adjust in fly.toml if needed)
- **CPU**: Shared CPU (1 core)
- **Volume**: 1GB (can be expanded)

## Monitoring

- Dashboard: https://fly.io/dashboard/personal
- Metrics: https://fly.io/apps/ph-beam/metrics
- Logs: `fly logs -a ph-beam`

## Useful Commands

```bash
# Deploy
fly deploy

# Check status
fly status -a ph-beam

# View logs
fly logs -a ph-beam

# SSH console
fly ssh console -a ph-beam

# List secrets
fly secrets list -a ph-beam

# Remove a secret
fly secrets unset SECRET_NAME -a ph-beam

# Restart application
fly apps restart ph-beam

# Open in browser
fly apps open -a ph-beam
```
