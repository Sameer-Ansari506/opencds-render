# OpenCDS Server - Render Deployment

OpenCDS Clinical Decision Support server deployed on Render.

## Quick Deploy

### 1. Commit and Push to GitHub

```bash
cd /Users/sameeransari/opencds-render

# Initialize git
git init
git add .
git commit -m "OpenCDS server ready for Render deployment"

# Create GitHub repo at: https://github.com/new
# Name: opencds-server
# Make it PUBLIC (required for Render free tier)
# Don't initialize with anything

# Push to GitHub
git remote add origin https://github.com/your-username/opencds-server.git
git branch -M main
git push -u origin main
```

### 2. Deploy on Render

1. Go to https://render.com
2. Sign up/login
3. Click **"New +"** → **"Web Service"**
4. Connect GitHub → Select `opencds-server`
5. Render will auto-detect `render.yaml`
6. Click **"Create Web Service"**
7. Wait 10-15 minutes for first build

### 3. Get Your Endpoint

After deployment:
```
https://your-service-name.onrender.com/opencds-decision-support-service/evaluate
```

### 4. Update Veda Configuration

In Veda backend `.env`:
```bash
OPENCDS_MOCK_MODE=false
OPENCDS_BASE_URL=https://your-service-name.onrender.com/opencds-decision-support-service/evaluate
```

## What's Included

- `opencds/` - OpenCDS source code (built on Render)
- `Dockerfile.build` - Multi-stage build (Maven → Tomcat)
- `render.yaml` - Render configuration

## Important Notes

- **First build**: 10-15 minutes (Maven downloads dependencies)
- **Java 17**: Required (configured in Dockerfile)
- **Free tier**: Sleeps after 15 min (first request ~30s delay)

## Verify Deployment

```bash
curl https://your-service-name.onrender.com/opencds/
```
