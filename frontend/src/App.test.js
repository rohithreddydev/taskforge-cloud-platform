import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import App from './App';

// Mock the API module with proper implementations
jest.mock('./services/api', () => ({
  get: jest.fn(),
  post: jest.fn(),
  put: jest.fn(),
  delete: jest.fn()
}));

// Mock react-toastify
jest.mock('react-toastify', () => ({
  toast: {
    success: jest.fn(),
    error: jest.fn(),
  },
  ToastContainer: () => null
}));

// Import the mocked api
const api = require('./services/api');

describe('App Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders without crashing', async () => {
    // Mock successful API responses
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ 
          data: [
            { 
              id: 1, 
              title: 'Test Task', 
              description: 'Test Description', 
              completed: false, 
              priority: 1, 
              created_at: new Date().toISOString() 
            }
          ] 
        });
      }
      if (url === '/stats') {
        return Promise.resolve({ 
          data: {
            total_tasks: 1,
            completed_tasks: 0,
            pending_tasks: 1,
            completion_rate: 0,
            priority_breakdown: { 1: 1, 2: 0, 3: 0 },
            tasks_created_today: 1
          }
        });
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Check that the app rendered
    expect(screen.getByText('Task Manager')).toBeInTheDocument();
  });

  test('displays loading spinner initially', async () => {
    // Create a promise that we can resolve later
    let resolvePromise;
    const promise = new Promise(resolve => { resolvePromise = resolve; });
    
    api.get.mockImplementation(() => promise);
    
    render(<App />);
    
    // Loading spinner should be visible immediately
    expect(screen.getByText('Loading tasks...')).toBeInTheDocument();
    
    // Resolve the promise
    resolvePromise({ data: [] });
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
  });

  test('displays task form', async () => {
    // Mock successful API responses
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ data: [] });
      }
      if (url === '/stats') {
        return Promise.resolve({ 
          data: {
            total_tasks: 0,
            completed_tasks: 0,
            pending_tasks: 0,
            completion_rate: 0,
            priority_breakdown: {},
            tasks_created_today: 0
          }
        });
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    expect(screen.getByText('Create New Task')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Enter task title')).toBeInTheDocument();
  });

  test('handles API errors gracefully', async () => {
    // Mock API to reject
    api.get.mockRejectedValue(new Error('Network error'));
    
    render(<App />);
    
    // Wait for error to be displayed
    await waitFor(() => {
      expect(screen.getByText('Failed to fetch tasks. Please try again.')).toBeInTheDocument();
    });
  });

  test('loads and displays tasks', async () => {
    // Mock successful API responses
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ 
          data: [
            { 
              id: 1, 
              title: 'Test Task', 
              description: 'Test Description', 
              completed: false, 
              priority: 1, 
              created_at: new Date().toISOString() 
            }
          ] 
        });
      }
      if (url === '/stats') {
        return Promise.resolve({ 
          data: {
            total_tasks: 1,
            completed_tasks: 0,
            pending_tasks: 1,
            completion_rate: 0,
            priority_breakdown: { 1: 1, 2: 0, 3: 0 },
            tasks_created_today: 1
          }
        });
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for tasks to load
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Check if task is displayed
    expect(screen.getByText('Test Task')).toBeInTheDocument();
    expect(screen.getByText('Test Description')).toBeInTheDocument();
  });

  test('displays statistics', async () => {
    // Mock successful API responses
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ 
          data: [
            { 
              id: 1, 
              title: 'Test Task', 
              description: 'Test Description', 
              completed: false, 
              priority: 1, 
              created_at: new Date().toISOString() 
            }
          ] 
        });
      }
      if (url === '/stats') {
        return Promise.resolve({ 
          data: {
            total_tasks: 1,
            completed_tasks: 0,
            pending_tasks: 1,
            completion_rate: 0,
            priority_breakdown: { 1: 1, 2: 0, 3: 0 },
            tasks_created_today: 1
          }
        });
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for stats to load
    await waitFor(() => {
      expect(screen.getByText('Total Tasks')).toBeInTheDocument();
    });
    
    // Check specific elements instead of just "1"
    expect(screen.getByText('Total Tasks')).toBeInTheDocument();
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('Today')).toBeInTheDocument();
    
    // Check the values - use getAllByText and check count or use more specific selectors
    const totalTasksValue = screen.getByText('Total Tasks').nextElementSibling;
    expect(totalTasksValue).toHaveTextContent('1');
    
    // Or check that there are 3 elements with "1" (Total, Pending, Today)
    const ones = screen.getAllByText('1');
    expect(ones.length).toBe(3);
  });

  test('displays empty state when no tasks', async () => {
    // Mock successful API responses with empty tasks
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ data: [] });
      }
      if (url === '/stats') {
        return Promise.resolve({ 
          data: {
            total_tasks: 0,
            completed_tasks: 0,
            pending_tasks: 0,
            completion_rate: 0,
            priority_breakdown: {},
            tasks_created_today: 0
          }
        });
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Check for empty state
    expect(screen.getByText('No Tasks Found')).toBeInTheDocument();
    expect(screen.getByText('Create your first task using the form on the left!')).toBeInTheDocument();
  });

  test('handles stats API error gracefully', async () => {
    // Mock tasks success but stats failure
    api.get.mockImplementation((url) => {
      if (url === '/tasks') {
        return Promise.resolve({ 
          data: [
            { 
              id: 1, 
              title: 'Test Task', 
              description: 'Test Description', 
              completed: false, 
              priority: 1, 
              created_at: new Date().toISOString() 
            }
          ] 
        });
      }
      if (url === '/stats') {
        return Promise.reject(new Error('Stats error'));
      }
      return Promise.resolve({ data: [] });
    });

    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Tasks should still display
    expect(screen.getByText('Test Task')).toBeInTheDocument();
    
    // Stats should not be displayed
    expect(screen.queryByText('Total Tasks')).not.toBeInTheDocument();
  });
});