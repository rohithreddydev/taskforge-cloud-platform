"""
Task Manager Backend API
Main application factory module
"""

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import os
import logging
import sys
from logging.handlers import RotatingFileHandler

# Initialize extensions without app
db = SQLAlchemy()
migrate = Migrate()
cors = CORS()
limiter = Limiter(key_func=get_remote_address, storage_uri="memory://")

def create_app(config_name=None):
    """
    Application factory function
    Creates and configures the Flask application
    """
    app = Flask(__name__)
    
    # Load configuration
    if config_name == 'testing':
        app.config.from_object('config.TestingConfig')
    elif config_name == 'production':
        app.config.from_object('config.ProductionConfig')
    else:
        app.config.from_object('config.DevelopmentConfig')
    
    # Initialize extensions with app
    db.init_app(app)
    migrate.init_app(app, db)
    cors.init_app(app, resources={r"/api/*": {"origins": "*"}})
    limiter.init_app(app)
    
    # Setup logging
    setup_logging(app)
    
    # Register routes
    register_blueprints(app)
    
    # Create tables
    with app.app_context():
        app.logger.info("Creating database tables...")
        db.create_all()
        app.logger.info("Database tables created successfully")
    
    return app

def setup_logging(app):
    """
    Configure logging for the application
    """
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
    
    app.logger.info('Application starting up...')
    app.logger.info(f"Environment: {app.config.get('ENV', 'development')}")
    app.logger.info(f"Database: {app.config.get('SQLALCHEMY_DATABASE_URI')}")

def register_blueprints(app):
    """
    Register all blueprints with the application
    """
    from routes import register_routes
    register_routes(app)

if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=app.config['DEBUG'])