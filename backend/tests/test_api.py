"""
Unit tests for the Task Manager API
"""

import pytest
import json
from datetime import datetime, timezone

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'
    assert 'services' in data
    assert 'database' in data['services']
    assert data['services']['database'] == 'connected'

def test_create_task(client):
    """Test task creation"""
    task_data = {
        'title': 'New Task',
        'description': 'Task Description',
        'completed': False,
        'priority': 2
    }
    
    response = client.post('/api/tasks', 
                          json=task_data,
                          content_type='application/json')
    
    assert response.status_code == 201, f"Expected 201, got {response.status_code}. Response: {response.data}"
    data = json.loads(response.data)
    assert data['title'] == task_data['title']
    assert data['description'] == task_data['description']
    assert data['priority'] == 2
    assert 'id' in data

def test_create_task_missing_title(client):
    """Test task creation with missing title"""
    task_data = {'description': 'No title'}
    
    response = client.post('/api/tasks', json=task_data)
    assert response.status_code == 400
    data = json.loads(response.data)
    assert 'error' in data

def test_get_tasks(client, sample_task):
    """Test getting all tasks"""
    response = client.get('/api/tasks')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert len(data) >= 1
    assert data[0]['title'] == 'Test Task'

def test_get_single_task(client, sample_task):
    """Test getting single task"""
    response = client.get(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['title'] == sample_task.title
    assert data['description'] == sample_task.description

def test_get_nonexistent_task(client):
    """Test getting a task that doesn't exist"""
    response = client.get('/api/tasks/99999')
    assert response.status_code == 404
    data = json.loads(response.data)
    assert 'error' in data

def test_update_task(client, sample_task):
    """Test updating task"""
    update_data = {
        'title': 'Updated Title',
        'completed': True,
        'priority': 3
    }
    
    response = client.put(f'/api/tasks/{sample_task.id}', 
                         json=update_data)
    
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['title'] == 'Updated Title'
    assert data['completed'] == True
    assert data['priority'] == 3

def test_delete_task(client, sample_task):
    """Test deleting task"""
    # Delete the task
    response = client.delete(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['message'] == 'Task deleted successfully'
    
    # Verify it's gone
    response = client.get(f'/api/tasks/{sample_task.id}')
    assert response.status_code == 404
    data = json.loads(response.data)
    assert 'error' in data

def test_get_stats(client, sample_task):
    """Test statistics endpoint"""
    response = client.get('/api/stats')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'total_tasks' in data
    assert 'completed_tasks' in data
    assert 'pending_tasks' in data
    assert 'completion_rate' in data

def test_metrics_endpoint(client, sample_task):
    """Test Prometheus metrics endpoint"""
    response = client.get('/metrics')
    assert response.status_code == 200
    content = response.data.decode()
    assert 'tasks_total' in content
    assert 'tasks_completed_total' in content

def test_batch_create_tasks(client):
    """Test batch task creation"""
    batch_data = {
        'tasks': [
            {'title': 'Task 1', 'description': 'First task'},
            {'title': 'Task 2', 'description': 'Second task'},
            {'title': 'Task 3', 'description': 'Third task'}
        ]
    }
    
    response = client.post('/api/tasks/batch', json=batch_data)
    assert response.status_code == 201
    data = json.loads(response.data)
    assert data['total_created'] == 3
    assert len(data['created']) == 3

def test_404_error(client):
    """Test 404 error handling"""
    response = client.get('/api/nonexistent/route')
    assert response.status_code == 404
    data = json.loads(response.data)
    assert 'error' in data
    assert data['error'] == 'Resource not found'

def test_method_not_allowed(client):
    """Test 405 method not allowed"""
    response = client.put('/health')  # Health endpoint only accepts GET
    assert response.status_code == 405
    data = json.loads(response.data)
    assert 'error' in data