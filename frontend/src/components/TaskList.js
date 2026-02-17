import React from 'react';
import { Card, Button, Badge, Form } from 'react-bootstrap';
import { FaEdit, FaTrash, FaFlag } from 'react-icons/fa';
import './TaskList.css';

const TaskList = ({ tasks, onEdit, onDelete, onToggleComplete }) => {
  const getPriorityBadge = (priority) => {
    const priorityMap = {
      1: { variant: 'success', label: 'Low' },
      2: { variant: 'warning', label: 'Medium' },
      3: { variant: 'danger', label: 'High' }
    };
    
    const { variant, label } = priorityMap[priority] || priorityMap[1];
    return <Badge bg={variant}><FaFlag /> {label}</Badge>;
  };

  if (tasks.length === 0) {
    return (
      <Card className="text-center p-5">
        <Card.Body>
          <Card.Title>No Tasks Found</Card.Title>
          <Card.Text>
            Create your first task using the form on the left!
          </Card.Text>
        </Card.Body>
      </Card>
    );
  }

  return (
    <div className="task-list">
      <h3 className="mb-3">
        Tasks ({tasks.length})
      </h3>
      
      {tasks.map(task => (
        <Card 
          key={task.id} 
          className={`mb-3 task-card ${task.completed ? 'completed' : ''}`}
        >
          <Card.Body>
            <div className="d-flex justify-content-between align-items-start">
              <div className="d-flex align-items-center">
                <Form.Check 
                  type="checkbox"
                  checked={task.completed}
                  onChange={() => onToggleComplete(task)}
                  className="me-3"
                  aria-label={`Mark task "${task.title}" as ${task.completed ? 'incomplete' : 'complete'}`}
                />
                <div>
                  <h5 className={task.completed ? 'text-muted text-decoration-line-through' : ''}>
                    {task.title}
                  </h5>
                  {task.description && (
                    <p className="text-muted mb-2">{task.description}</p>
                  )}
                  <div className="d-flex gap-2">
                    {getPriorityBadge(task.priority)}
                  </div>
                </div>
              </div>
              
              <div className="task-actions">
                <Button 
                  variant="outline-warning" 
                  size="sm"
                  onClick={() => onEdit(task)}
                  className="me-2"
                  aria-label={`Edit task: ${task.title}`}
                >
                  <FaEdit />
                </Button>
                <Button 
                  variant="outline-danger" 
                  size="sm"
                  onClick={() => onDelete(task.id)}
                  aria-label={`Delete task: ${task.title}`}
                >
                  <FaTrash />
                </Button>
              </div>
            </div>
          </Card.Body>
        </Card>
      ))}
    </div>
  );
};

export default TaskList;