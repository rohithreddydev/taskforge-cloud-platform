"""
Task Manager Backend API
A production-ready Flask application with PostgreSQL database
Includes: logging, error handling, health checks, metrics
"""

from flask import Flask, request, jsonify, g
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import os
import datetime
import logging
import traceback
import sys
from logging.handlers import RotatingFileHandler
from prometheus_flask_exporter import PrometheusMetrics
import redis
import json

# Initialize Flask app
app = Flask(__name__)


# Configuration class
class Config:
    """Application configuration"""

    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-key-change-in-production")
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "postgresql://postgres:password@localhost:5432/taskdb"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_size": 10,
        "pool_recycle": 300,
        "pool_pre_ping": True,
    }
    REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
    DEBUG = os.environ.get("FLASK_DEBUG", "False").lower() == "true"
    ENV = os.environ.get("FLASK_ENV", "production")


app.config.from_object(Config)

# Initialize extensions
db = SQLAlchemy(app)
migrate = Migrate(app, db)
CORS(app, resources={r"/api/*": {"origins": "*"}})

# Initialize Redis for caching
redis_client = redis.from_url(app.config["REDIS_URL"])

# Initialize Prometheus metrics
metrics = PrometheusMetrics(app, path="/metrics")
metrics.info("app_info", "Application version", version="1.0.0")

# Rate limiting
limiter = Limiter(
    app=app, key_func=get_remote_address, default_limits=["200 per day", "50 per hour"]
)


# Setup logging
def setup_logging():
    """Configure logging for production"""
    log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

    # Create logs directory if it doesn't exist
    if not os.path.exists("logs"):
        os.makedirs("logs")

    # File handler for all logs
    file_handler = RotatingFileHandler(
        "logs/app.log", maxBytes=10485760, backupCount=10  # 10MB
    )
    file_handler.setFormatter(logging.Formatter(log_format))
    file_handler.setLevel(logging.INFO)

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter(log_format))
    console_handler.setLevel(logging.DEBUG if app.debug else logging.INFO)

    # Add handlers
    app.logger.addHandler(file_handler)
    app.logger.addHandler(console_handler)
    app.logger.setLevel(logging.DEBUG if app.debug else logging.INFO)

    # Log startup
    app.logger.info("Application starting up...")
    app.logger.info(f"Environment: {app.config['ENV']}")
    app.logger.info(f"Debug mode: {app.debug}")


setup_logging()


# Database Models
class Task(db.Model):
    """Task model for the todo application"""

    __tablename__ = "tasks"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False, index=True)
    description = db.Column(db.Text)
    completed = db.Column(db.Boolean, default=False, index=True)
    priority = db.Column(db.Integer, default=1)  # 1: Low, 2: Medium, 3: High
    due_date = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow, index=True)
    updated_at = db.Column(
        db.DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow
    )
    completed_at = db.Column(db.DateTime, nullable=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    def to_dict(self):
        """Convert task to dictionary"""
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "completed": self.completed,
            "priority": self.priority,
            "due_date": self.due_date.isoformat() if self.due_date else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "completed_at": (
                self.completed_at.isoformat() if self.completed_at else None
            ),
        }

    def __repr__(self):
        return f"<Task {self.id}: {self.title}>"


class User(db.Model):
    """User model for authentication (extend later)"""

    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(128))
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow)
    tasks = db.relationship("Task", backref="user", lazy="dynamic")


# Create tables
@app.before_first_request
def create_tables():
    """Create database tables on first request"""
    app.logger.info("Creating database tables...")
    db.create_all()
    app.logger.info("Database tables created successfully")


# Error Handlers
@app.errorhandler(404)
def not_found_error(error):
    """Handle 404 errors"""
    app.logger.warning(f"404 error: {request.path}")
    return jsonify({"error": "Resource not found"}), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    db.session.rollback()
    app.logger.error(f"500 error: {str(error)}\n{traceback.format_exc()}")
    return jsonify({"error": "Internal server error"}), 500


@app.errorhandler(429)
def ratelimit_error(error):
    """Handle rate limit errors"""
    app.logger.warning(f"Rate limit exceeded for {request.remote_addr}")
    return jsonify({"error": "Rate limit exceeded. Please try again later."}), 429


# Middleware for request logging
@app.before_request
def before_request():
    """Log each request"""
    g.start_time = datetime.datetime.utcnow()
    app.logger.debug(f"Request: {request.method} {request.path}")


@app.after_request
def after_request(response):
    """Log response time"""
    if hasattr(g, "start_time"):
        duration = (datetime.datetime.utcnow() - g.start_time).total_seconds() * 1000
        app.logger.debug(f"Response: {response.status_code} - {duration:.2f}ms")
    return response


# Health check endpoints
@app.route("/health", methods=["GET"])
def health_check():
    """
    Health check endpoint for Kubernetes liveness probe
    Returns 200 if app is healthy, 500 if unhealthy
    """
    health_status = {
        "status": "healthy",
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "services": {},
    }

    # Check database connection
    try:
        db.session.execute("SELECT 1")
        health_status["services"]["database"] = "connected"
    except Exception as e:
        app.logger.error(f"Database health check failed: {str(e)}")
        health_status["services"]["database"] = "disconnected"
        health_status["status"] = "unhealthy"

    # Check Redis connection
    try:
        redis_client.ping()
        health_status["services"]["redis"] = "connected"
    except Exception as e:
        app.logger.error(f"Redis health check failed: {str(e)}")
        health_status["services"]["redis"] = "disconnected"
        health_status["status"] = "unhealthy"

    # Return appropriate status code
    status_code = 200 if health_status["status"] == "healthy" else 500
    return jsonify(health_status), status_code


@app.route("/ready", methods=["GET"])
def readiness_check():
    """
    Readiness check endpoint for Kubernetes readiness probe
    Returns 200 when app is ready to serve traffic
    """
    return (
        jsonify(
            {"status": "ready", "timestamp": datetime.datetime.utcnow().isoformat()}
        ),
        200,
    )


# API Routes
@app.route("/api/tasks", methods=["GET"])
@limiter.limit("100 per minute")
def get_tasks():
    """
    Get all tasks with optional filtering
    Query params: completed (bool), priority (int), search (string)
    """
    try:
        app.logger.info("Fetching tasks")

        # Get query parameters
        completed = request.args.get("completed")
        priority = request.args.get("priority", type=int)
        search = request.args.get("search")

        # Build query
        query = Task.query

        if completed is not None:
            completed_bool = completed.lower() == "true"
            query = query.filter_by(completed=completed_bool)
            app.logger.debug(f"Filtering by completed: {completed_bool}")

        if priority:
            query = query.filter_by(priority=priority)
            app.logger.debug(f"Filtering by priority: {priority}")

        if search:
            query = query.filter(Task.title.ilike(f"%{search}%"))
            app.logger.debug(f"Searching for: {search}")

        # Order by created_at desc
        query = query.order_by(Task.created_at.desc())

        # Execute query
        tasks = query.all()

        # Cache in Redis for future requests
        cache_key = f"tasks:{request.query_string}"
        try:
            redis_client.setex(
                cache_key,
                30,  # Cache for 30 seconds
                json.dumps([task.to_dict() for task in tasks]),
            )
        except Exception as e:
            app.logger.warning(f"Redis cache set failed: {str(e)}")

        app.logger.info(f"Retrieved {len(tasks)} tasks")
        return jsonify([task.to_dict() for task in tasks]), 200

    except Exception as e:
        app.logger.error(f"Error fetching tasks: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Failed to fetch tasks"}), 500


@app.route("/api/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    """Get a single task by ID"""
    try:
        app.logger.info(f"Fetching task {task_id}")

        # Try to get from cache first
        cache_key = f"task:{task_id}"
        try:
            cached_task = redis_client.get(cache_key)
            if cached_task:
                app.logger.debug(f"Task {task_id} found in cache")
                return jsonify(json.loads(cached_task)), 200
        except Exception as e:
            app.logger.warning(f"Redis cache get failed: {str(e)}")

        # Get from database
        task = Task.query.get(task_id)

        if task:
            task_dict = task.to_dict()
            # Cache for future requests
            try:
                redis_client.setex(cache_key, 60, json.dumps(task_dict))
            except Exception as e:
                app.logger.warning(f"Redis cache set failed: {str(e)}")

            return jsonify(task_dict), 200

        app.logger.warning(f"Task {task_id} not found")
        return jsonify({"error": "Task not found"}), 404

    except Exception as e:
        app.logger.error(
            f"Error fetching task {task_id}: {str(e)}\n{traceback.format_exc()}"
        )
        return jsonify({"error": "Failed to fetch task"}), 500


@app.route("/api/tasks", methods=["POST"])
@limiter.limit("50 per minute")
def create_task():
    """Create a new task"""
    try:
        app.logger.info("Creating new task")

        # Get and validate request data
        data = request.get_json()

        if not data:
            app.logger.warning("No JSON data provided")
            return jsonify({"error": "No data provided"}), 400

        if "title" not in data or not data["title"].strip():
            app.logger.warning("Task creation failed: missing title")
            return jsonify({"error": "Title is required"}), 400

        # Create task object
        task = Task(
            title=data["title"].strip(),
            description=data.get("description", "").strip(),
            completed=data.get("completed", False),
            priority=data.get("priority", 1),
            due_date=(
                datetime.datetime.fromisoformat(data["due_date"])
                if data.get("due_date")
                else None
            ),
        )

        # Save to database
        db.session.add(task)
        db.session.commit()

        # Invalidate cache
        try:
            redis_client.delete("tasks:*")
        except Exception as e:
            app.logger.warning(f"Redis cache invalidation failed: {str(e)}")

        app.logger.info(f"Task created successfully: {task.title} (ID: {task.id})")
        return jsonify(task.to_dict()), 201

    except ValueError as e:
        app.logger.warning(f"Invalid data format: {str(e)}")
        return jsonify({"error": "Invalid data format"}), 400
    except Exception as e:
        db.session.rollback()
        app.logger.error(f"Error creating task: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Failed to create task"}), 500


@app.route("/api/tasks/<int:task_id>", methods=["PUT"])
def update_task(task_id):
    """Update an existing task"""
    try:
        app.logger.info(f"Updating task {task_id}")

        # Get task
        task = Task.query.get(task_id)
        if not task:
            app.logger.warning(f"Task {task_id} not found for update")
            return jsonify({"error": "Task not found"}), 404

        # Get update data
        data = request.get_json()

        if not data:
            app.logger.warning("No JSON data provided for update")
            return jsonify({"error": "No data provided"}), 400

        # Track if completed status changed
        was_completed = task.completed

        # Update fields
        if "title" in data:
            task.title = data["title"].strip()
        if "description" in data:
            task.description = data["description"].strip()
        if "completed" in data and data["completed"] != task.completed:
            task.completed = data["completed"]
            if data["completed"]:
                task.completed_at = datetime.datetime.utcnow()
            else:
                task.completed_at = None
        if "priority" in data:
            task.priority = data["priority"]
        if "due_date" in data:
            task.due_date = (
                datetime.datetime.fromisoformat(data["due_date"])
                if data["due_date"]
                else None
            )

        # Save changes
        db.session.commit()

        # Invalidate caches
        try:
            redis_client.delete(f"task:{task_id}")
            redis_client.delete("tasks:*")
        except Exception as e:
            app.logger.warning(f"Redis cache invalidation failed: {str(e)}")

        app.logger.info(f"Task {task_id} updated successfully")
        return jsonify(task.to_dict()), 200

    except ValueError as e:
        app.logger.warning(f"Invalid data format for update: {str(e)}")
        return jsonify({"error": "Invalid data format"}), 400
    except Exception as e:
        db.session.rollback()
        app.logger.error(
            f"Error updating task {task_id}: {str(e)}\n{traceback.format_exc()}"
        )
        return jsonify({"error": "Failed to update task"}), 500


@app.route("/api/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    """Delete a task"""
    try:
        app.logger.info(f"Deleting task {task_id}")

        task = Task.query.get(task_id)
        if not task:
            app.logger.warning(f"Task {task_id} not found for deletion")
            return jsonify({"error": "Task not found"}), 404

        db.session.delete(task)
        db.session.commit()

        # Invalidate caches
        try:
            redis_client.delete(f"task:{task_id}")
            redis_client.delete("tasks:*")
        except Exception as e:
            app.logger.warning(f"Redis cache invalidation failed: {str(e)}")

        app.logger.info(f"Task {task_id} deleted successfully")
        return jsonify({"message": "Task deleted successfully"}), 200

    except Exception as e:
        db.session.rollback()
        app.logger.error(
            f"Error deleting task {task_id}: {str(e)}\n{traceback.format_exc()}"
        )
        return jsonify({"error": "Failed to delete task"}), 500


@app.route("/api/tasks/batch", methods=["POST"])
@limiter.limit("10 per minute")
def batch_create_tasks():
    """Create multiple tasks in batch"""
    try:
        app.logger.info("Batch creating tasks")

        data = request.get_json()

        if not data or "tasks" not in data:
            return jsonify({"error": "Tasks array required"}), 400

        tasks_data = data["tasks"]
        created_tasks = []
        errors = []

        for idx, task_data in enumerate(tasks_data):
            try:
                if "title" not in task_data:
                    errors.append({"index": idx, "error": "Title required"})
                    continue

                task = Task(
                    title=task_data["title"].strip(),
                    description=task_data.get("description", "").strip(),
                    completed=task_data.get("completed", False),
                )
                db.session.add(task)
                created_tasks.append(task)

            except Exception as e:
                errors.append({"index": idx, "error": str(e)})

        db.session.commit()

        # Invalidate cache
        try:
            redis_client.delete("tasks:*")
        except Exception as e:
            app.logger.warning(f"Redis cache invalidation failed: {str(e)}")

        app.logger.info(
            f"Batch created {len(created_tasks)} tasks with {len(errors)} errors"
        )

        return (
            jsonify(
                {
                    "created": [task.to_dict() for task in created_tasks],
                    "errors": errors,
                    "total_created": len(created_tasks),
                    "total_errors": len(errors),
                }
            ),
            201,
        )

    except Exception as e:
        db.session.rollback()
        app.logger.error(f"Error in batch create: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Failed to create tasks"}), 500


@app.route("/api/stats", methods=["GET"])
def get_stats():
    """Get task statistics"""
    try:
        app.logger.info("Fetching task statistics")

        # Get statistics
        total_tasks = Task.query.count()
        completed_tasks = Task.query.filter_by(completed=True).count()
        pending_tasks = total_tasks - completed_tasks

        # Priority breakdown
        priority_counts = {
            1: Task.query.filter_by(priority=1).count(),
            2: Task.query.filter_by(priority=2).count(),
            3: Task.query.filter_by(priority=3).count(),
        }

        # Tasks created today
        today = datetime.datetime.utcnow().date()
        tasks_today = Task.query.filter(db.func.date(Task.created_at) == today).count()

        stats = {
            "total_tasks": total_tasks,
            "completed_tasks": completed_tasks,
            "pending_tasks": pending_tasks,
            "completion_rate": (
                (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
            ),
            "priority_breakdown": priority_counts,
            "tasks_created_today": tasks_today,
            "timestamp": datetime.datetime.utcnow().isoformat(),
        }

        return jsonify(stats), 200

    except Exception as e:
        app.logger.error(f"Error fetching stats: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Failed to fetch statistics"}), 500


# CLI commands
@app.cli.command("create-admin")
def create_admin():
    """Create admin user (CLI command)"""
    username = input("Username: ")
    email = input("Email: ")
    password = input("Password: ")

    # In production, hash the password
    user = User(username=username, email=email)
    db.session.add(user)
    db.session.commit()

    print(f"Admin user {username} created successfully")


@app.cli.command("cleanup-old-tasks")
def cleanup_old_tasks():
    """Delete tasks older than 30 days (CLI command)"""
    cutoff_date = datetime.datetime.utcnow() - datetime.timedelta(days=30)
    old_tasks = Task.query.filter(Task.created_at < cutoff_date).delete()
    db.session.commit()
    print(f"Deleted {old_tasks} old tasks")


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5000)),
        debug=app.config["DEBUG"],
    )
