import React, { useState, useEffect } from 'react';
import { Form, Button, Card } from 'react-bootstrap';

const TaskForm = ({ onSubmit, initialData, onCancel }) => {
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    priority: 1,
    due_date: ''
  });
  const [validated, setValidated] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (initialData) {
      setFormData({
        title: initialData.title || '',
        description: initialData.description || '',
        priority: initialData.priority || 1,
        due_date: initialData.due_date ? initialData.due_date.slice(0, 10) : ''
      });
    }
  }, [initialData]);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData({
      ...formData,
      [name]: value
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    const form = e.currentTarget;
    if (!form.checkValidity()) {
      e.stopPropagation();
      setValidated(true);
      return;
    }

    if (!formData.title.trim()) {
      alert('Title is required');
      return;
    }

    setSubmitting(true);
    const success = await onSubmit(formData);
    setSubmitting(false);
    
    if (success && !initialData) {
      setFormData({
        title: '',
        description: '',
        priority: 1,
        due_date: ''
      });
      setValidated(false);
    }
  };

  return (
    <Card>
      <Card.Header>
        <h4>{initialData ? 'Edit Task' : 'Create New Task'}</h4>
      </Card.Header>
      <Card.Body>
        <Form noValidate validated={validated} onSubmit={handleSubmit}>
          <Form.Group className="mb-3" controlId="taskTitle">
            <Form.Label>Title *</Form.Label>
            <Form.Control
              type="text"
              name="title"
              value={formData.title}
              onChange={handleChange}
              required
              placeholder="Enter task title"
            />
            <Form.Control.Feedback type="invalid">
              Title is required
            </Form.Control.Feedback>
          </Form.Group>

          <Form.Group className="mb-3" controlId="taskDescription">
            <Form.Label>Description</Form.Label>
            <Form.Control
              as="textarea"
              name="description"
              value={formData.description}
              onChange={handleChange}
              rows={3}
              placeholder="Enter task description"
            />
          </Form.Group>

          <Form.Group className="mb-3" controlId="taskPriority">
            <Form.Label>Priority</Form.Label>
            <Form.Select
              name="priority"
              value={formData.priority}
              onChange={handleChange}
            >
              <option value={1}>Low</option>
              <option value={2}>Medium</option>
              <option value={3}>High</option>
            </Form.Select>
          </Form.Group>

          <Form.Group className="mb-3" controlId="taskDueDate">
            <Form.Label>Due Date</Form.Label>
            <Form.Control
              type="date"
              name="due_date"
              value={formData.due_date}
              onChange={handleChange}
            />
          </Form.Group>

          <div className="d-grid gap-2">
            <Button 
              type="submit" 
              variant="primary"
              disabled={submitting}
            >
              {submitting ? 'Saving...' : (initialData ? 'Update Task' : 'Create Task')}
            </Button>
            
            {initialData && (
              <Button 
                type="button" 
                variant="secondary"
                onClick={onCancel}
              >
                Cancel
              </Button>
            )}
          </div>
        </Form>
      </Card.Body>
    </Card>
  );
};

export default TaskForm;
