import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import TaskList from './TaskList';

const mockTasks = [
  {
    id: 1,
    title: 'Test Task 1',
    description: 'Description 1',
    completed: false,
    priority: 1,
    created_at: '2026-01-01T00:00:00Z'
  },
  {
    id: 2,
    title: 'Test Task 2',
    description: 'Description 2',
    completed: true,
    priority: 2,
    created_at: '2026-01-02T00:00:00Z'
  }
];

const mockProps = {
  tasks: mockTasks,
  onEdit: jest.fn(),
  onDelete: jest.fn(),
  onToggleComplete: jest.fn()
};

describe('TaskList Component', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders task list', () => {
    render(<TaskList {...mockProps} />);
    
    expect(screen.getByText('Tasks (2)')).toBeInTheDocument();
    expect(screen.getByText('Test Task 1')).toBeInTheDocument();
    expect(screen.getByText('Test Task 2')).toBeInTheDocument();
  });

  test('calls onEdit when edit button is clicked', () => {
    render(<TaskList {...mockProps} />);
    
    const editButtons = screen.getAllByLabelText(/Edit task/i);
    fireEvent.click(editButtons[0]);
    
    expect(mockProps.onEdit).toHaveBeenCalledWith(mockTasks[0]);
  });

  test('calls onDelete when delete button is clicked', () => {
    render(<TaskList {...mockProps} />);
    
    const deleteButtons = screen.getAllByLabelText(/Delete task/i);
    fireEvent.click(deleteButtons[0]);
    
    expect(mockProps.onDelete).toHaveBeenCalledWith(1);
  });

  test('calls onToggleComplete when checkbox is clicked', () => {
    render(<TaskList {...mockProps} />);
    
    const checkboxes = screen.getAllByRole('checkbox');
    fireEvent.click(checkboxes[0]);
    
    expect(mockProps.onToggleComplete).toHaveBeenCalledWith(mockTasks[0]);
  });

  test('displays empty state when no tasks', () => {
    render(<TaskList {...mockProps} tasks={[]} />);
    
    expect(screen.getByText('No Tasks Found')).toBeInTheDocument();
    expect(screen.getByText('Create your first task using the form on the left!')).toBeInTheDocument();
  });
});