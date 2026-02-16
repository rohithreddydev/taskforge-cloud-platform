import React from 'react';
import { render, screen } from '@testing-library/react';
import TaskStats from './TaskStats';

const mockStats = {
  total_tasks: 10,
  completed_tasks: 4,
  pending_tasks: 6,
  completion_rate: 40,
  priority_breakdown: {
    '1': 5,
    '2': 3,
    '3': 2
  },
  tasks_created_today: 2
};

describe('TaskStats Component', () => {
  test('renders statistics correctly', () => {
    render(<TaskStats stats={mockStats} />);
    
    expect(screen.getByText('Total Tasks')).toBeInTheDocument();
    expect(screen.getByText('10')).toBeInTheDocument();
    
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    
    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('6')).toBeInTheDocument();
    
    expect(screen.getByText('Today')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    
    expect(screen.getByText('Completion Rate: 40.0%')).toBeInTheDocument();
  });

  test('handles empty stats gracefully', () => {
    render(<TaskStats stats={{}} />);
    
    expect(screen.getByText('Total Tasks')).toBeInTheDocument();
    expect(screen.getAllByText('0').length).toBeGreaterThan(0);
  });

  test('displays priority breakdown', () => {
    render(<TaskStats stats={mockStats} />);
    
    expect(screen.getByText(/Priority Breakdown/i)).toBeInTheDocument();
    expect(screen.getByText('Low: 5')).toBeInTheDocument();
    expect(screen.getByText('Medium: 3')).toBeInTheDocument();
    expect(screen.getByText('High: 2')).toBeInTheDocument();
  });
});