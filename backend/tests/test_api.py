"""
Unit tests for the Task Manager API
Run with: pytest -v --cov=. --cov-report=term
"""

import pytest
import json
import sys
import os

# Add the parent directory to path so we can import app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app, db, Task

@pytest.fixture
def client():
    """Create test client"""
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    
    with app.test_client() as client:
        with app.app_context():
            db.create_all()
            yield client
            db.session.remove()
            db.drop_all()

@pytest.fixture
def sample_task():
    """Create sample task for tests"""
    with app.app_context():
        task = Task(
            title="Test Task",
            description="Test Description",
            completed=False
        )
        db.session.add(task)
        db.session.commit()
        return task

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'

def test_create_task(client):
    """Test task creation"""
    task_data = {
        'title': 'New Task',
        'description': 'Task Description',
        'completed': False
    }
    
    response = client.post('/api/tasks', 
                          json=task_data,
                          content_type='application/json')
    
    assert response.status_code == 201
    data = json.loads(response.data)
    assert data['title'] == task_data['title']
    assert data['description'] == task_data['description']
    assert 'id' in data

def test_create_task_missing_title(client):
    """Test task creation with missing title"""
    task_data = {'description': 'No title'}
    
    response = client.post('/api/tasks', json=task_data)
    assert response.status_code == 400

def test_get_tasks(client, sample_task):
    """Test getting all tasks"""
    response = client.get('/api/tasks')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert len(data) >= 1

def test_get_single_task(client, sample_task):
    """Test getting single task"""
    response = client.get(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['title'] == sample_task.title

def test_update_task(client, sample_task):
    """Test updating task"""
    update_data = {'title': 'Updated Title', 'completed': True}
    
    response = client.put(f'/api/tasks/{sample_task.id}', 
                         json=update_data)
    
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['title'] == 'Updated Title'
    assert data['completed'] == True

def test_delete_task(client, sample_task):
    """Test deleting task"""
    response = client.delete(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 200
    
    # Verify deletion
    response = client.get(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 404

def test_batch_create_tasks(client):
    """Test batch creation"""
    batch_data = {
        'tasks': [
            {'title': 'Task 1', 'description': 'First'},
            {'title': 'Task 2', 'description': 'Second'},
            {'title': 'Task 3', 'description': 'Third'}
        ]
    }
    
    response = client.post('/api/tasks/batch', json=batch_data)
    assert response.status_code == 201
    data = json.loads(response.data)
    assert data['total_created'] == 3

def test_get_stats(client, sample_task):
    """Test statistics endpoint"""
    response = client.get('/api/stats')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'total_tasks' in data
    assert 'completion_rate' in data

def test_404_error(client):
    """Test 404 handling"""
    response = client.get('/api/nonexistent')
    assert response.status_code == 404