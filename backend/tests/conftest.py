"""
Pytest configuration and fixtures for testing
"""

import pytest
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import create_app, db
from models import Task

@pytest.fixture(scope='function')
def app():
    """Create application for testing"""
    app = create_app('testing')
    
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()

@pytest.fixture
def client(app):
    """Create test client"""
    return app.test_client()

@pytest.fixture
def runner(app):
    """Create test CLI runner"""
    return app.test_cli_runner()

@pytest.fixture
def sample_task(app):
    """Create sample task for tests"""
    with app.app_context():
        task = Task(
            title="Test Task",
            description="Test Description",
            completed=False,
            priority=1
        )
        db.session.add(task)
        db.session.commit()
        db.session.refresh(task)
        return task