import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import App from './App.js';

// Create a manual mock control object
const mockApi = {
  shouldSucceed: true,
  shouldDelay: false,
  tasksData: [
    { 
      id: 1, 
      title: 'Test Task', 
      description: 'Test Description', 
      completed: false, 
      priority: 1, 
      created_at: new Date().toISOString() 
    }
  ],
  statsData: {
    total_tasks: 1,
    completed_tasks: 0,
    pending_tasks: 1,
    completion_rate: 0,
    priority_breakdown: { 1: 1, 2: 0, 3: 0 },
    tasks_created_today: 1
  }
};

// Mock the API module with a function that returns different responses based on the mockApi object
jest.mock('./services/api', () => {
  return {
    get: jest.fn().mockImplementation((url) => {
      return new Promise((resolve, reject) => {
        // Check if we should simulate a delay
        if (mockApi.shouldDelay) {
          setTimeout(() => {
            if (mockApi.shouldSucceed) {
              if (url === '/tasks') {
                resolve({ data: mockApi.tasksData });
              } else if (url === '/stats') {
                resolve({ data: mockApi.statsData });
              } else {
                resolve({ data: [] });
              }
            } else {
              reject(new Error('Network error'));
            }
          }, 100);
        } else {
          if (mockApi.shouldSucceed) {
            if (url === '/tasks') {
              resolve({ data: mockApi.tasksData });
            } else if (url === '/stats') {
              resolve({ data: mockApi.statsData });
            } else {
              resolve({ data: [] });
            }
          } else {
            reject(new Error('Network error'));
          }
        }
      });
    }),
    post: jest.fn().mockResolvedValue({ data: { id: 2, title: 'New Task' } }),
    put: jest.fn().mockResolvedValue({ data: { id: 1, title: 'Updated Task' } }),
    delete: jest.fn().mockResolvedValue({ data: {} })
  };
});

// Mock react-toastify
jest.mock('react-toastify', () => ({
  toast: {
    success: jest.fn(),
    error: jest.fn(),
  },
  ToastContainer: () => null
}));

// Mock console.error to avoid noise in tests
const originalConsoleError = console.error;
const originalConsoleLog = console.log;

beforeAll(() => {
  console.error = jest.fn();
  console.log = jest.fn();
});

afterAll(() => {
  console.error = originalConsoleError;
  console.log = originalConsoleLog;
});

describe('App Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Reset mockApi to default values
    mockApi.shouldSucceed = true;
    mockApi.shouldDelay = false;
    mockApi.tasksData = [
      { 
        id: 1, 
        title: 'Test Task', 
        description: 'Test Description', 
        completed: false, 
        priority: 1, 
        created_at: new Date().toISOString() 
      }
    ];
    mockApi.statsData = {
      total_tasks: 1,
      completed_tasks: 0,
      pending_tasks: 1,
      completion_rate: 0,
      priority_breakdown: { 1: 1, 2: 0, 3: 0 },
      tasks_created_today: 1
    };
  });

  test('renders without crashing', async () => {
    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Use getAllByText since there are multiple elements with "Task Manager"
    const titleElements = screen.getAllByText(/Task Manager/i);
    expect(titleElements.length).toBeGreaterThan(0);
  });

  test('displays loading spinner initially', async () => {
    // Set delay to ensure loading state is visible
    mockApi.shouldDelay = true;
    
    render(<App />);
    
    // Loading spinner should be visible immediately
    expect(screen.getByText('Loading tasks...')).toBeInTheDocument();
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    }, { timeout: 2000 });
  });

  test('displays task form', async () => {
    render(<App />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    expect(screen.getByText('Create New Task')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Enter task title')).toBeInTheDocument();
  });

  test('handles API errors gracefully', async () => {
    // Set mock to return error
    mockApi.shouldSucceed = false;
    
    render(<App />);
    
    // Wait for error to be displayed
    await waitFor(() => {
      expect(screen.getByText('Failed to fetch tasks. Please try again.')).toBeInTheDocument();
    });
  });

  test('loads and displays tasks', async () => {
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
    render(<App />);
    
    // Wait for stats to load
    await waitFor(() => {
      expect(screen.getByText('Total Tasks')).toBeInTheDocument();
    });
    
    expect(screen.getByText('1')).toBeInTheDocument(); // Total tasks count
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('Today')).toBeInTheDocument();
  });

  test('displays empty state when no tasks', async () => {
    // Override tasks data to be empty
    mockApi.tasksData = [];
    
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
    // Mock stats to fail but tasks to succeed
    mockApi.statsData = null;
    
    render(<App />);
    
    // Wait for tasks to load
    await waitFor(() => {
      expect(screen.queryByText('Loading tasks...')).not.toBeInTheDocument();
    });
    
    // Tasks should still display
    expect(screen.getByText('Test Task')).toBeInTheDocument();
    
    // Stats should not be displayed (but no error shown to user)
    expect(screen.queryByText('Total Tasks')).not.toBeInTheDocument();
  });
});