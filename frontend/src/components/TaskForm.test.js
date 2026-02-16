import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import TaskForm from './TaskForm';

const mockProps = {
  onSubmit: jest.fn().mockResolvedValue(true),
  onCancel: jest.fn(),
  initialData: null
};

describe('TaskForm Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders create task form', () => {
    render(<TaskForm {...mockProps} />);
    
    expect(screen.getByText('Create New Task')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Enter task title')).toBeInTheDocument();
    expect(screen.getByText('Create Task')).toBeInTheDocument();
  });

  test('renders edit task form', () => {
    const editProps = {
      ...mockProps,
      initialData: {
        id: 1,
        title: 'Edit Task',
        description: 'Edit Description',
        priority: 2
      }
    };
    
    render(<TaskForm {...editProps} />);
    
    expect(screen.getByText('Edit Task')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Edit Task')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Edit Description')).toBeInTheDocument();
    expect(screen.getByText('Update Task')).toBeInTheDocument();
    expect(screen.getByText('Cancel')).toBeInTheDocument();
  });

  test('submits form with valid data', async () => {
    render(<TaskForm {...mockProps} />);
    
    fireEvent.change(screen.getByPlaceholderText('Enter task title'), {
      target: { value: 'New Test Task' }
    });
    
    fireEvent.change(screen.getByPlaceholderText('Enter task description'), {
      target: { value: 'New Description' }
    });
    
    fireEvent.click(screen.getByText('Create Task'));
    
    await waitFor(() => {
      expect(mockProps.onSubmit).toHaveBeenCalledWith({
        title: 'New Test Task',
        description: 'New Description',
        priority: 1,
        due_date: ''
      });
    });
  });

  test('shows validation error for empty title', () => {
    render(<TaskForm {...mockProps} />);
    
    fireEvent.click(screen.getByText('Create Task'));
    
    expect(screen.getByText('Title is required')).toBeInTheDocument();
    expect(mockProps.onSubmit).not.toHaveBeenCalled();
  });

  test('calls onCancel when cancel button is clicked', () => {
    const editProps = {
      ...mockProps,
      initialData: { id: 1, title: 'Test' }
    };
    
    render(<TaskForm {...editProps} />);
    
    fireEvent.click(screen.getByText('Cancel'));
    expect(mockProps.onCancel).toHaveBeenCalled();
  });
});