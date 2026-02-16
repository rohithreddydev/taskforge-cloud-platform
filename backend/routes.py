"""
Route handlers for the Task Manager API
"""

import datetime
import json
import traceback
from flask import request, jsonify, g
from sqlalchemy import text
from models import db, Task, User


def get_utc_now():
    """Helper function to get current UTC time (handles deprecation)"""
    if hasattr(datetime, "UTC"):
        # Python 3.11+
        return datetime.datetime.now(datetime.UTC)
    else:
        # Older Python versions
        return datetime.datetime.utcnow()


def register_routes(app):
    """Register all routes with the Flask app"""

    # ============ HEALTH CHECKS ============
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
            db.session.execute(text("SELECT 1"))
            health_status["services"]["database"] = "connected"
        except Exception as e:
            app.logger.error(f"Database health check failed: {str(e)}")
            health_status["services"]["database"] = "disconnected"
            health_status["status"] = "unhealthy"

        # Check Redis connection
        if hasattr(app, "redis_client") and app.redis_client:
            try:
                app.redis_client.ping()
                health_status["services"]["redis"] = "connected"
            except Exception as e:
                app.logger.error(f"Redis health check failed: {str(e)}")
                health_status["services"]["redis"] = "disconnected"
                health_status["status"] = "unhealthy"
        else:
            health_status["services"]["redis"] = "not_configured"

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

    # ============ TASK ROUTES ============
    @app.route("/api/tasks", methods=["GET"])
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

            # Cache in Redis for future requests (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                cache_key = f"tasks:{request.query_string}"
                try:
                    app.redis_client.setex(
                        cache_key,
                        30,  # Cache for 30 seconds
                        json.dumps([task.to_dict() for task in tasks]),
                    )
                except Exception as e:
                    app.logger.warning(f"Redis cache set failed: {str(e)}")

            app.logger.info(f"Retrieved {len(tasks)} tasks")
            return jsonify([task.to_dict() for task in tasks]), 200

        except Exception as e:
            app.logger.error(
                f"Error fetching tasks: {str(e)}\n{traceback.format_exc()}"
            )
            return jsonify({"error": "Failed to fetch tasks"}), 500

    @app.route("/api/tasks/<int:task_id>", methods=["GET"])
    def get_task(task_id):
        """Get a single task by ID"""
        try:
            app.logger.info(f"Fetching task {task_id}")

            # Try to get from cache first (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                cache_key = f"task:{task_id}"
                try:
                    cached_task = app.redis_client.get(cache_key)
                    if cached_task:
                        app.logger.debug(f"Task {task_id} found in cache")
                        return jsonify(json.loads(cached_task)), 200
                except Exception as e:
                    app.logger.warning(f"Redis cache get failed: {str(e)}")

            # Get from database
            task = Task.query.get(task_id)

            if task:
                task_dict = task.to_dict()
                # Cache for future requests (if Redis is available)
                if hasattr(app, "redis_client") and app.redis_client:
                    try:
                        app.redis_client.setex(cache_key, 60, json.dumps(task_dict))
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
            )

            # Handle due_date if provided
            if data.get("due_date"):
                try:
                    task.due_date = datetime.datetime.fromisoformat(
                        data["due_date"].replace("Z", "+00:00")
                    )
                except ValueError:
                    app.logger.warning(f"Invalid due_date format: {data['due_date']}")

            # Save to database
            db.session.add(task)
            db.session.commit()

            # Invalidate cache (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                try:
                    # Delete all task list caches
                    for key in app.redis_client.scan_iter("tasks:*"):
                        app.redis_client.delete(key)
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
                if data["due_date"]:
                    try:
                        task.due_date = datetime.datetime.fromisoformat(
                            data["due_date"].replace("Z", "+00:00")
                        )
                    except ValueError:
                        task.due_date = None
                else:
                    task.due_date = None

            # Save changes
            db.session.commit()

            # Invalidate caches (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                try:
                    app.redis_client.delete(f"task:{task_id}")
                    for key in app.redis_client.scan_iter("tasks:*"):
                        app.redis_client.delete(key)
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

            # Invalidate caches (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                try:
                    app.redis_client.delete(f"task:{task_id}")
                    for key in app.redis_client.scan_iter("tasks:*"):
                        app.redis_client.delete(key)
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

            # Invalidate cache (if Redis is available)
            if hasattr(app, "redis_client") and app.redis_client:
                try:
                    for key in app.redis_client.scan_iter("tasks:*"):
                        app.redis_client.delete(key)
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
            app.logger.error(
                f"Error in batch create: {str(e)}\n{traceback.format_exc()}"
            )
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
            tasks_today = Task.query.filter(
                db.func.date(Task.created_at) == today
            ).count()

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
            app.logger.error(
                f"Error fetching stats: {str(e)}\n{traceback.format_exc()}"
            )
            return jsonify({"error": "Failed to fetch statistics"}), 500
