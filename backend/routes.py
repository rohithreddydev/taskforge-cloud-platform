"""
Task Manager Backend API
Route definitions and request handlers
"""

from flask import jsonify, request, make_response
from sqlalchemy import text
from datetime import datetime, timezone
import json

# Import models and db from app
from app import db
from models import Task

def register_routes(app):
    """
    Register all routes with the Flask application
    """
    
    # Error handlers
    @app.errorhandler(404)
    def not_found_error(error):
        """Handle 404 errors with JSON response"""
        return jsonify({'error': 'Resource not found'}), 404

    @app.errorhandler(500)
    def internal_error(error):
        """Handle 500 errors"""
        db.session.rollback()
        app.logger.error(f"500 error: {error}")
        return jsonify({'error': 'Internal server error'}), 500

    @app.errorhandler(405)
    def method_not_allowed(error):
        """Handle 405 errors"""
        return jsonify({'error': 'Method not allowed'}), 405

    @app.errorhandler(400)
    def bad_request_error(error):
        """Handle 400 errors"""
        return jsonify({'error': 'Bad request'}), 400
    
    @app.route('/health', methods=['GET'])
    def health_check():
        """
        Health check endpoint for Kubernetes liveness probe
        Returns 200 if app is healthy, 500 if unhealthy
        """
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': {}
        }
        
        try:
            # Check database connection
            db.session.execute(text('SELECT 1'))
            health_status['services']['database'] = 'connected'
        except Exception as e:
            app.logger.error(f"Database health check failed: {e}")
            health_status['services']['database'] = 'disconnected'
            health_status['status'] = 'unhealthy'
        
        # Return appropriate status code
        status_code = 200 if health_status['status'] == 'healthy' else 500
        return jsonify(health_status), status_code

    @app.route('/ready', methods=['GET'])
    def readiness_check():
        """
        Readiness check endpoint for Kubernetes readiness probe
        Returns 200 when app is ready to serve traffic
        """
        return jsonify({
            'status': 'ready',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }), 200

    @app.route('/api/tasks', methods=['GET'])
    def get_tasks():
        """
        Get all tasks with optional filtering
        Query params: completed (bool), priority (int), search (string)
        """
        try:
            app.logger.info("Fetching tasks")
            
            # Get query parameters
            completed = request.args.get('completed')
            priority = request.args.get('priority', type=int)
            search = request.args.get('search')
            
            # Build query
            query = db.session.query(Task)
            
            if completed is not None:
                completed_bool = completed.lower() == 'true'
                query = query.filter_by(completed=completed_bool)
                app.logger.debug(f"Filtering by completed: {completed_bool}")
            
            if priority:
                query = query.filter_by(priority=priority)
                app.logger.debug(f"Filtering by priority: {priority}")
            
            if search:
                query = query.filter(Task.title.ilike(f'%{search}%'))
                app.logger.debug(f"Searching for: {search}")
            
            # Order by created_at desc
            query = query.order_by(Task.created_at.desc())
            
            # Execute query
            tasks = query.all()
            
            app.logger.info(f"Retrieved {len(tasks)} tasks")
            return jsonify([task.to_dict() for task in tasks]), 200
            
        except Exception as e:
            app.logger.error(f"Error fetching tasks: {e}")
            return jsonify({'error': 'Failed to fetch tasks'}), 500

    @app.route('/api/tasks/<int:task_id>', methods=['GET'])
    def get_task(task_id):
        """
        Get a single task by ID
        """
        try:
            app.logger.info(f"Fetching task {task_id}")
            
            # Use Session.get() instead of Query.get() for SQLAlchemy 2.0
            task = db.session.get(Task, task_id)
            
            if task:
                return jsonify(task.to_dict()), 200
            
            app.logger.warning(f"Task {task_id} not found")
            return jsonify({'error': 'Task not found'}), 404
            
        except Exception as e:
            app.logger.error(f"Error fetching task {task_id}: {e}")
            return jsonify({'error': 'Failed to fetch task'}), 500

    @app.route('/api/tasks', methods=['POST'])
    def create_task():
        """
        Create a new task
        """
        try:
            app.logger.info("Creating new task")
            
            # Get and validate request data
            data = request.get_json()
            
            if not data:
                app.logger.warning("No JSON data provided")
                return jsonify({'error': 'No data provided'}), 400
            
            if 'title' not in data or not data['title'].strip():
                app.logger.warning("Task creation failed: missing title")
                return jsonify({'error': 'Title is required'}), 400
            
            # Create task object - don't set user_id if not provided
            task = Task(
                title=data['title'].strip(),
                description=data.get('description', '').strip(),
                completed=data.get('completed', False),
                priority=data.get('priority', 1)
            )
            
            # Handle due_date if provided
            if data.get('due_date'):
                try:
                    task.due_date = datetime.fromisoformat(data['due_date'].replace('Z', '+00:00'))
                except:
                    app.logger.warning(f"Invalid due_date format: {data['due_date']}")
            
            # Save to database
            db.session.add(task)
            db.session.commit()
            
            app.logger.info(f"Task created successfully: {task.title} (ID: {task.id})")
            return jsonify(task.to_dict()), 201
            
        except Exception as e:
            db.session.rollback()
            app.logger.error(f"Error creating task: {e}")
            return jsonify({'error': 'Failed to create task'}), 500

    @app.route('/api/tasks/<int:task_id>', methods=['PUT'])
    def update_task(task_id):
        """
        Update an existing task
        """
        try:
            app.logger.info(f"Updating task {task_id}")
            
            # Get task using Session.get() for SQLAlchemy 2.0
            task = db.session.get(Task, task_id)
            if not task:
                app.logger.warning(f"Task {task_id} not found for update")
                return jsonify({'error': 'Task not found'}), 404
            
            # Get update data
            data = request.get_json()
            
            if not data:
                app.logger.warning("No JSON data provided for update")
                return jsonify({'error': 'No data provided'}), 400
            
            # Update fields
            if 'title' in data:
                task.title = data['title'].strip()
            if 'description' in data:
                task.description = data['description'].strip()
            if 'completed' in data and data['completed'] != task.completed:
                task.completed = data['completed']
                if data['completed']:
                    task.completed_at = datetime.now(timezone.utc)
                else:
                    task.completed_at = None
            if 'priority' in data:
                task.priority = data['priority']
            if 'due_date' in data:
                if data['due_date']:
                    try:
                        task.due_date = datetime.fromisoformat(data['due_date'].replace('Z', '+00:00'))
                    except:
                        task.due_date = None
                else:
                    task.due_date = None
            
            # Save changes
            db.session.commit()
            
            app.logger.info(f"Task {task_id} updated successfully")
            return jsonify(task.to_dict()), 200
            
        except Exception as e:
            db.session.rollback()
            app.logger.error(f"Error updating task {task_id}: {e}")
            return jsonify({'error': 'Failed to update task'}), 500

    @app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
    def delete_task(task_id):
        """
        Delete a task
        """
        try:
            app.logger.info(f"Deleting task {task_id}")
            
            # Get task using Session.get() for SQLAlchemy 2.0
            task = db.session.get(Task, task_id)
            if not task:
                app.logger.warning(f"Task {task_id} not found for deletion")
                return jsonify({'error': 'Task not found'}), 404
            
            db.session.delete(task)
            db.session.commit()
            
            app.logger.info(f"Task {task_id} deleted successfully")
            return jsonify({'message': 'Task deleted successfully'}), 200
            
        except Exception as e:
            db.session.rollback()
            app.logger.error(f"Error deleting task {task_id}: {e}")
            return jsonify({'error': 'Failed to delete task'}), 500

    @app.route('/api/tasks/batch', methods=['POST'])
    def batch_create_tasks():
        """
        Create multiple tasks in batch
        """
        try:
            app.logger.info("Batch creating tasks")
            
            data = request.get_json()
            
            if not data or 'tasks' not in data:
                return jsonify({'error': 'Tasks array required'}), 400
            
            tasks_data = data['tasks']
            created_tasks = []
            errors = []
            
            for idx, task_data in enumerate(tasks_data):
                try:
                    if 'title' not in task_data:
                        errors.append({'index': idx, 'error': 'Title required'})
                        continue
                    
                    task = Task(
                        title=task_data['title'].strip(),
                        description=task_data.get('description', '').strip(),
                        completed=task_data.get('completed', False)
                    )
                    db.session.add(task)
                    created_tasks.append(task)
                    
                except Exception as e:
                    errors.append({'index': idx, 'error': str(e)})
            
            db.session.commit()
            
            app.logger.info(f"Batch created {len(created_tasks)} tasks with {len(errors)} errors")
            
            return jsonify({
                'created': [task.to_dict() for task in created_tasks],
                'errors': errors,
                'total_created': len(created_tasks),
                'total_errors': len(errors)
            }), 201
            
        except Exception as e:
            db.session.rollback()
            app.logger.error(f"Error in batch create: {e}")
            return jsonify({'error': 'Failed to create tasks'}), 500

    @app.route('/api/stats', methods=['GET'])
    def get_stats():
        """
        Get task statistics
        """
        try:
            app.logger.info("Fetching task statistics")
            
            total_tasks = db.session.query(Task).count()
            completed_tasks = db.session.query(Task).filter_by(completed=True).count()
            pending_tasks = total_tasks - completed_tasks
            
            # Priority breakdown
            priority_counts = {
                1: db.session.query(Task).filter_by(priority=1).count(),
                2: db.session.query(Task).filter_by(priority=2).count(),
                3: db.session.query(Task).filter_by(priority=3).count()
            }
            
            # Tasks created today
            today = datetime.now(timezone.utc).date()
            tasks_today = db.session.query(Task).filter(
                db.func.date(Task.created_at) == today
            ).count()
            
            stats = {
                'total_tasks': total_tasks,
                'completed_tasks': completed_tasks,
                'pending_tasks': pending_tasks,
                'completion_rate': (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0,
                'priority_breakdown': priority_counts,
                'tasks_created_today': tasks_today,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            
            return jsonify(stats), 200
            
        except Exception as e:
            app.logger.error(f"Error fetching stats: {e}")
            return jsonify({'error': 'Failed to fetch statistics'}), 500

    @app.route('/metrics', methods=['GET'])
    def metrics():
        """
        Prometheus metrics endpoint
        """
        try:
            total_tasks = db.session.query(Task).count()
            completed_tasks = db.session.query(Task).filter_by(completed=True).count()
            
            return f"""# HELP tasks_total Total number of tasks
# TYPE tasks_total gauge
tasks_total {total_tasks}

# HELP tasks_completed_total Number of completed tasks
# TYPE tasks_completed_total gauge
tasks_completed_total {completed_tasks}
""", 200, {'Content-Type': 'text/plain'}
            
        except Exception as e:
            app.logger.error(f"Error generating metrics: {e}")
            return "", 500