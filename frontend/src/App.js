import React, { useState, useEffect } from 'react';
import { Container, Navbar, Alert, Spinner } from 'react-bootstrap';
import { ToastContainer, toast } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';
import 'bootstrap/dist/css/bootstrap.min.css';
import './App.css';
import TaskList from './components/TaskList';
import TaskForm from './components/TaskForm';
import TaskStats from './components/TaskStats';
import api from './services/api';

function App() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [editingTask, setEditingTask] = useState(null);
  const [stats, setStats] = useState(null);

  // Fetch tasks on component mount
  useEffect(() => {
    fetchTasks();
  }, []);

  // Fetch statistics periodically
  useEffect(() => {
    fetchStats();
    const interval = setInterval(fetchStats, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchTasks = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await api.get('/tasks');
      setTasks(response.data);
    } catch (err) {
      setError('Failed to fetch tasks. Please try again.');
      toast.error('Failed to fetch tasks: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  const fetchStats = async () => {
    try {
      const response = await api.get('/stats');
      if (response && response.data) {
        setStats(response.data);
      }
    } catch (err) {
      // Silently fail for stats - don't show error to user
      console.log('Stats fetch failed');
    }
  };

  const createTask = async (taskData) => {
    try {
      const response = await api.post('/tasks', taskData);
      setTasks([response.data, ...tasks]);
      fetchStats();
      toast.success('Task created successfully!');
      return true;
    } catch (err) {
      toast.error('Failed to create task: ' + err.message);
      return false;
    }
  };

  const updateTask = async (id, taskData) => {
    try {
      const response = await api.put(`/tasks/${id}`, taskData);
      setTasks(tasks.map(task => task.id === id ? response.data : task));
      fetchStats();
      toast.success('Task updated successfully!');
      setEditingTask(null);
      return true;
    } catch (err) {
      toast.error('Failed to update task: ' + err.message);
      return false;
    }
  };

  const deleteTask = async (id) => {
    if (!window.confirm('Are you sure you want to delete this task?')) return;
    
    try {
      await api.delete(`/tasks/${id}`);
      setTasks(tasks.filter(task => task.id !== id));
      fetchStats();
      toast.success('Task deleted successfully!');
    } catch (err) {
      toast.error('Failed to delete task: ' + err.message);
    }
  };

  const toggleComplete = async (task) => {
    await updateTask(task.id, { ...task, completed: !task.completed });
  };

  return (
    <div className="App">
      <Navbar bg="primary" variant="dark" expand="lg">
        <Container>
          <Navbar.Brand href="/">
            Task Manager
          </Navbar.Brand>
        </Container>
      </Navbar>

      <Container className="mt-4">
        {error && (
          <Alert variant="danger" onClose={() => setError(null)} dismissible>
            {error}
          </Alert>
        )}

        {/* Statistics Section */}
        {stats && <TaskStats stats={stats} />}

        <div className="row">
          <div className="col-md-4">
            <TaskForm 
              onSubmit={editingTask ? 
                (data) => updateTask(editingTask.id, data) : 
                createTask
              }
              initialData={editingTask}
              onCancel={() => setEditingTask(null)}
            />
          </div>
          
          <div className="col-md-8">
            {loading ? (
              <div className="text-center mt-5">
                <Spinner animation="border" variant="primary" />
                <p className="mt-2">Loading tasks...</p>
              </div>
            ) : (
              <TaskList 
                tasks={tasks} 
                onEdit={setEditingTask}
                onDelete={deleteTask}
                onToggleComplete={toggleComplete}
              />
            )}
          </div>
        </div>
      </Container>

      <footer className="bg-light text-center text-muted py-3 mt-5">
        <Container>
          <small>Task Manager App © 2026</small>
        </Container>
      </footer>

      <ToastContainer 
        position="bottom-right"
        autoClose={3000}
        hideProgressBar={false}
        newestOnTop
        closeOnClick
        rtl={false}
        pauseOnFocusLoss
        draggable
        pauseOnHover
      />
    </div>
  );
}

export default App;