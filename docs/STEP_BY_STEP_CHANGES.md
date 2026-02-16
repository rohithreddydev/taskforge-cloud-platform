# Step-by-Step Changes for TaskForge

Follow these steps in order. Each step is self-contained; you can stop after any phase.

---

## Phase 1: Critical Fixes (Do First)

### Step 1: Fix Redis cache invalidation

**Why:** `redis.delete('tasks:*')` does not support wildcards; cache is never cleared.

**What to do:**

1. Open `backend/app.py`.
2. Add a helper that invalidates task caches using Redis SCAN. For example:

   ```python
   def invalidate_task_caches():
       """Delete all keys matching tasks:* using SCAN (Redis doesn't support wildcard in DELETE)."""
       try:
           cursor = 0
           while True:
               cursor, keys = redis_client.scan(cursor=cursor, match='tasks:*', count=100)
               if keys:
                   redis_client.delete(*keys)
               if cursor == 0:
                   break
       except Exception as e:
           app.logger.warning(f"Redis cache invalidation failed: {str(e)}")
   ```

3. Replace every occurrence of:
   - `redis_client.delete('tasks:*')`  
   with a call to `invalidate_task_caches()`.
4. Replace every occurrence of:
   - `redis_client.delete(f"task:{task_id}")` and then `redis_client.delete('tasks:*')`  
   with: delete the single key `task:{task_id}` and then call `invalidate_task_caches()`.

**Files:** `backend/app.py` (create_task, update_task, delete_task, batch_create_tasks).

---

### Step 2: Replace deprecated Flask `before_first_request`

**Why:** `@app.before_first_request` is deprecated and may be removed.

**What to do:**

1. In `backend/app.py`, remove the `@app.before_first_request` decorator from `create_tables()`.
2. Call table creation at app startup instead. After `setup_logging()`, add:

   ```python
   with app.app_context():
       db.create_all()
       app.logger.info("Database tables created/verified")
   ```

3. Remove the `create_tables` function or keep it only for explicit CLI/script use.

**Files:** `backend/app.py`.

---

### Step 3: Ensure frontend has a lockfile for CI

**Why:** CI uses `npm ci` with `package-lock.json`; without it the job fails.

**What to do:**

1. In the `frontend/` directory run: `npm install` (this creates/updates `package-lock.json`).
2. Commit `frontend/package-lock.json`.
3. If you prefer not to use a lockfile, change `.github/workflows/ci.yml` to use `npm install` and set `cache-dependency-path: frontend/package.json` instead.

**Files:** `frontend/package-lock.json` (add to repo) or `.github/workflows/ci.yml`.

---

### Step 4: Verify backend Service port in Kubernetes

**Why:** Ingress may route to port 80 while the backend container serves 5000.

**What to do:**

1. Open `kubernetes/backend-service.yaml`.
2. Ensure the Service `targetPort` matches the container port (5000). For example:

   ```yaml
   spec:
     ports:
       - port: 80
         targetPort: 5000  # must match container port
   ```

3. In `kubernetes/ingress.yaml`, the backend path should reference this Service port (e.g. 80); the Service will forward to 5000.

**Files:** `kubernetes/backend-service.yaml`, `kubernetes/ingress.yaml`.

---

### Step 5: Parameterize Kubernetes manifests

**Why:** Placeholders like `<aws-account-id>` and hardcoded RDS/Redis hosts break real deployments.

**What to do:**

1. **Choose a strategy:** Kustomize (overlays), Helm, or simple envsubst.
2. **Backend image:**
   - In `kubernetes/backend-deployment.yaml`, replace `<aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/task-manager-backend:latest` with a placeholder like `$(ECR_REGISTRY)/task-manager-backend:$(IMAGE_TAG)` and substitute in CI/CD, or use Kustomize `image` patch / Helm values.
3. **ConfigMap/Secrets:**
   - In `kubernetes/configmap.yaml`, replace hardcoded `DB_HOST`, `REDIS_HOST`, etc., with placeholders or use a Kustomize configMapGenerator / Helm.
   - In `kubernetes/secrets.yaml`, do not commit real secrets; use placeholders and inject from Terraform outputs or a secret manager in CD.
4. **Ingress:**
   - In `kubernetes/ingress.yaml`, replace placeholder ARNs (e.g. certificate, WAF, security group) with variables or Kustomize/Helm values filled in per environment.

**Files:** All under `kubernetes/` (backend-deployment, frontend deployment, configmap, secrets, ingress).

---

### Step 6: Add a CD (deploy) pipeline

**Why:** Images are built and pushed but not deployed to EKS.

**What to do:**

1. Add a deploy job in `.github/workflows/ci.yml` (or a new workflow, e.g. `deploy.yml`) that runs after the build job on `main` (and optionally `develop`).
2. In the deploy job:
   - Checkout code.
   - Configure AWS credentials and `kubectl` (e.g. `aws eks update-kubeconfig`).
   - Substitute image tag (e.g. short SHA or branch) into manifests (if using envsubst) or use `kubectl set image deployment/...`.
   - Run `kubectl apply` for the target namespace (e.g. `task-manager` for prod, `task-manager-staging` for staging).
3. Store `KUBECONFIG` or use OIDC for EKS access; avoid long-lived AWS keys if possible.

**Files:** `.github/workflows/ci.yml` or `.github/workflows/deploy.yml`.

---

## Phase 2: Authentication

### Step 7: Backend – JWT and auth endpoints

**What to do:**

1. Add dependencies: e.g. `Flask-JWT-Extended`, `bcrypt` (or `werkzeug.security` for hashing). Add to `backend/requirements.txt`.
2. Configure JWT in `backend/app.py` (secret, algorithm, expiry).
3. Implement:
   - `POST /api/auth/register`: create User, hash password, return user (and optionally token).
   - `POST /api/auth/login`: verify password, return JWT.
   - `GET /api/auth/me`: return current user from JWT (protected).
4. Protect all `/api/tasks` routes: require a valid JWT and set `user_id` from token. For existing tasks without `user_id`, decide policy (e.g. assign to current user or leave unscoped until you migrate).

**Files:** `backend/app.py`, `backend/requirements.txt`.

---

### Step 8: Frontend – Login and auth flow

**What to do:**

1. Add routes (e.g. `/login`, `/register`) and components: `Login.js`, `Register.js`.
2. On successful login/register, store the JWT (e.g. in `localStorage`) and set it in the Axios interceptor (you already have a placeholder in `frontend/src/services/api.js`).
3. Add a simple auth context or check: if no token and route is protected, redirect to `/login`.
4. Call `GET /api/auth/me` on app load to validate token and load user; on 401, clear token and redirect to login.
5. Ensure all task API calls send the Bearer token (already prepared in `api.js`).

**Files:** `frontend/src/` (new components, routing in `app.js`, `api.js`).

---

## Phase 3: Production Hardening

### Step 9: Use Flask-Migrate for schema changes

**What to do:**

1. You already have Flask-Migrate in `requirements.txt`. Ensure `migrate = Migrate(app, db)` is in place.
2. Replace “create tables on startup” with migrations:
   - Run `flask db init` if not done, then `flask db migrate -m "Initial"`, then `flask db upgrade`.
3. In production startup (e.g. in Docker/K8s), run `flask db upgrade` before starting the app instead of `db.create_all()`.

**Files:** `backend/app.py`, new `migrations/` folder, Dockerfile/start script.

---

### Step 10: Monitoring and alerts

**What to do:**

1. Ensure Prometheus scrapes `/metrics` from the backend (already in deployment annotations).
2. Add a Grafana dashboard for request rate, errors, latency, and Redis/DB health.
3. Configure alerts (e.g. in Prometheus/Alertmanager or Grafana) for:
   - Health check failures
   - High error rate or latency
   - Redis/PostgreSQL down

**Files:** `monitoring/prometheus-config.yaml`, new Grafana dashboard JSON (optional), alert rules.

---

## Phase 4: Optional Enhancements

- **Step 11:** Add task categories or tags (DB column or new table, API filters, UI).
- **Step 12:** Add subtasks or checklist items (new model, nested API, UI).
- **Step 13:** Add recurring tasks (cron or background job to create instances).
- **Step 14:** Document RDS backup and restore procedure and test it once.

---

## Quick reference – files to touch

| Step | Primary files |
|------|----------------|
| 1 | `backend/app.py` |
| 2 | `backend/app.py` |
| 3 | `frontend/package-lock.json` or `.github/workflows/ci.yml` |
| 4 | `kubernetes/backend-service.yaml` |
| 5 | `kubernetes/*.yaml` (deployments, configmap, secrets, ingress) |
| 6 | `.github/workflows/ci.yml` or `.github/workflows/deploy.yml` |
| 7 | `backend/app.py`, `backend/requirements.txt` |
| 8 | `frontend/src/` (new pages + app.js + api.js) |
| 9 | `backend/app.py`, `backend/migrations/`, Docker/start script |
| 10 | `monitoring/`, Grafana, alerting |

After Phase 1 you’ll have a deployable, cache-correct, and CI/CD-ready base. Add Phase 2 for auth, then Phase 3 for production hardening.
