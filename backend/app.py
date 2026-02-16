"""
Task Manager Backend API
A production-ready Flask application with PostgreSQL database
Includes: logging, error handling, health checks, metrics
"""

import os
import datetime
import logging
import sys
import traceback  # Make sure this is imported
from logging.handlers import RotatingFileHandler

from flask import Flask, request, jsonify, g  # Make sure request is imported
from flask_migrate import Migrate
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from prometheus_flask_exporter import PrometheusMetrics
import redis

from models import db
from routes import register_routes

# Initialize extensions
migrate = Migrate()
limiter = Limiter(key_func=get_remote_address)
metrics = None

def get_utc_now():
    """Helper function to get current UTC time (handles deprecation)"""
    if hasattr(datetime, 'UTC'):
        # Python 3.11+
        return datetime.datetime.now(datetime.UTC)
    else:
        # Older Python versions
        return datetime.datetime.utcnow()

def create_app():
    """Application factory pattern"""
    app = Flask(__name__)
    
    # Configuration class
    class Config:
        """Application configuration"""
        SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
        SQLALCHEMY_DATABASE_URI = os.environ.get(
            'DATABASE_URL', 
            'postgresql://rohithsama@localhost:5432/taskdb'
        )
        SQLALCHEMY_TRACK_MODIFICATIONS = False
        SQLALCHEMY_ENGINE_OPTIONS = {
            'pool_size': 10,
            'pool_recycle': 300,
            'pool_pre_ping': True,
        }
        REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
        DEBUG = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
        ENV = os.environ.get('FLASK_ENV', 'production')

    app.config.from_object(Config)
    
    # Initialize extensions with app
    db.init_app(app)
    migrate.init_app(app, db)
    CORS(app, resources={r"/api/*": {"origins": "*"}})
    
    # Initialize Prometheus metrics
    global metrics
    metrics = PrometheusMetrics(app, path='/metrics')
    metrics.info('app_info', 'Application version', version='1.0.0')
    
    # Rate limiting with app
    limiter.init_app(app)
    
    # Setup logging
    setup_logging(app)
    
    # Initialize Redis for caching
    init_redis(app)
    
    # Register error handlers
    register_error_handlers(app)
    
    # Register middleware
    register_middleware(app)
    
    # Register routes
    register_routes(app)
    
    # Register CLI commands
    register_commands(app)
    
    # Create tables if they don't exist
    with app.app_context():
        app.logger.info("Creating database tables if they don't exist...")
        db.create_all()
        app.logger.info("Database tables created/verified successfully")
    
    return app

def setup_logging(app):
    """Configure logging for production"""
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # Create logs directory if it doesn't exist
    if not os.path.exists('logs'):
        os.makedirs('logs')
    
    # File handler for all logs
    file_handler = RotatingFileHandler(
        'logs/app.log', 
        maxBytes=10485760,  # 10MB
        backupCount=10
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
    app.logger.info('Application starting up...')
    app.logger.info(f"Environment: {app.config['ENV']}")
    app.logger.info(f"Debug mode: {app.debug}")

def init_redis(app):
    """Initialize Redis client"""
    try:
        app.redis_client = redis.from_url(
            app.config['REDIS_URL'], 
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2
        )
        app.redis_client.ping()
        app.logger.info("Redis connected successfully")
    except Exception as e:
        app.redis_client = None
        app.logger.warning(f"Redis connection failed - caching disabled: {str(e)}")

def register_error_handlers(app):
    """Register error handlers"""
    
    @app.errorhandler(404)
    def not_found_error(error):
        """Handle 404 errors"""
        app.logger.warning(f"404 error: {request.path}")
        return jsonify({'error': 'Resource not found'}), 404

    @app.errorhandler(500)
    def internal_error(error):
        """Handle 500 errors"""
        db.session.rollback()
        app.logger.error(f"500 error: {str(error)}\n{traceback.format_exc()}")
        return jsonify({'error': 'Internal server error'}), 500

    @app.errorhandler(429)
    def ratelimit_error(error):
        """Handle rate limit errors"""
        app.logger.warning(f"Rate limit exceeded for {request.remote_addr}")
        return jsonify({'error': 'Rate limit exceeded. Please try again later.'}), 429

def register_middleware(app):
    """Register middleware"""
    
    @app.before_request
    def before_request():
        """Log each request"""
        g.start_time = get_utc_now()  # Use helper function
        app.logger.debug(f"Request: {request.method} {request.path}")

    @app.after_request
    def after_request(response):
        """Log response time"""
        if hasattr(g, 'start_time'):
            duration = (get_utc_now() - g.start_time).total_seconds() * 1000
            app.logger.debug(f"Response: {response.status_code} - {duration:.2f}ms")
        return response

def register_commands(app):
    """Register CLI commands"""
    
    @app.cli.command('create-admin')
    def create_admin():
        """Create admin user (CLI command)"""
        from models import User
        
        username = input('Username: ')
        email = input('Email: ')
        password = input('Password: ')
        
        # In production, hash the password
        user = User(username=username, email=email)
        db.session.add(user)
        db.session.commit()
        
        print(f'Admin user {username} created successfully')

    @app.cli.command('cleanup-old-tasks')
    def cleanup_old_tasks():
        """Delete tasks older than 30 days (CLI command)"""
        from models import Task
        
        cutoff_date = get_utc_now() - datetime.timedelta(days=30)
        old_tasks = Task.query.filter(Task.created_at < cutoff_date).delete()
        db.session.commit()
        print(f'Deleted {old_tasks} old tasks')

# Create the app instance
app = create_app()

if __name__ == '__main__':
    app.run(
        host='0.0.0.0',
        port=int(os.environ.get('PORT', 5000)),
        debug=app.config['DEBUG']
    )