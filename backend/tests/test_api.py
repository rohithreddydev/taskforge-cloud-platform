"""
API tests for the Task Manager application
"""
import pytest
import json
from typing import Generator, Any

# Import the app factory
from app import create_app
# Import models directly
from models import db, Task, User


@pytest.fixture
def app() -> Generator[Any, Any, Any]:
    """Create test app"""
    app = create_app()
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture
def client(app) -> Generator[Any, Any, Any]:
    """Create test client"""
    return app.test_client()


def test_health_endpoint(client) -> None:
    """Test health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'


def test_create_task(client) -> None:
    """Test task creation"""
    task_data = {
        'title': 'Test Task',
        'description': 'This is a test task',
        'priority': 2
    }
    
    response = client.post(
        '/api/tasks',
        data=json.dumps(task_data),
        content_type='application/json'
    )
    
    assert response.status_code == 201
    data = json.loads(response.data)
    assert data['title'] == 'Test Task'
    assert data['description'] == 'This is a test task'
    assert data['priority'] == 2
    assert 'id' in data


def test_get_tasks(client) -> None:
    """Test getting all tasks"""
    # First create a task
    task_data = {'title': 'Another Task'}
    client.post(
        '/api/tasks',
        data=json.dumps(task_data),
        content_type='application/json'
    )
    
    # Then get all tasks
    response = client.get('/api/tasks')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert len(data) >= 1
    assert data[0]['title'] == 'Another Task'
