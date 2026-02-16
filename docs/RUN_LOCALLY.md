# Run TaskForge Locally

## Prerequisites

- **Docker** (for Postgres + Redis)
- **Python 3.11 or 3.12** (recommended; 3.14 can have dependency build issues)
- **Node.js 18+** and npm

## 1. Start database and Redis

```bash
docker compose up -d
```

Wait a few seconds, then check:

```bash
docker compose ps
```

## 2. Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

export DATABASE_URL="postgresql://postgres:password@localhost:5432/taskdb"
export REDIS_URL="redis://localhost:6379/0"
export FLASK_DEBUG=true

python app.py
```

Backend runs at **http://localhost:5000**.  
Health: http://localhost:5000/health  
API: http://localhost:5000/api/tasks  

## 3. Frontend (new terminal)

```bash
cd frontend
npm install
npm start
```

Frontend runs at **http://localhost:3000** and proxies API requests to the backend.

## Troubleshooting

- **Docker "credentials" error**: Fix Docker login/Keychain (e.g. Docker Desktop → Sign in, or remove stored credentials and re-login).
- **pg_config not found**: Install Postgres dev headers (e.g. `brew install postgresql` on macOS) or use Docker only for Postgres and run the app on the host.
- **npm not found**: Install Node.js (e.g. from nodejs.org or `brew install node`) or use nvm/fnm and ensure the shell loads it.
