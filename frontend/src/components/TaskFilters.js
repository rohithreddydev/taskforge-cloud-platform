import React from 'react';
import { Form, Row, Col, Button } from 'react-bootstrap';

const TaskFilters = ({ filters, onFilterChange, onClearFilters }) => {
  const handleChange = (e) => {
    const { name, value } = e.target;
    onFilterChange({ [name]: value });
  };

  return (
    <div className="filters-section mb-3">
      <Row>
        <Col md={4}>
          <Form.Group controlId="filterSearch">
            <Form.Label>Search</Form.Label>
            <Form.Control
              type="text"
              name="search"
              value={filters.search}
              onChange={handleChange}
              placeholder="Search tasks..."
            />
          </Form.Group>
        </Col>
        
        <Col md={3}>
          <Form.Group controlId="filterCompleted">
            <Form.Label>Status</Form.Label>
            <Form.Select
              name="completed"
              value={filters.completed}
              onChange={handleChange}
            >
              <option value="">All</option>
              <option value="true">Completed</option>
              <option value="false">Pending</option>
            </Form.Select>
          </Form.Group>
        </Col>
        
        <Col md={3}>
          <Form.Group controlId="filterPriority">
            <Form.Label>Priority</Form.Label>
            <Form.Select
              name="priority"
              value={filters.priority}
              onChange={handleChange}
            >
              <option value="">All</option>
              <option value="1">Low</option>
              <option value="2">Medium</option>
              <option value="3">High</option>
            </Form.Select>
          </Form.Group>
        </Col>
        
        <Col md={2} className="d-flex align-items-end">
          <Button 
            variant="outline-secondary" 
            onClick={onClearFilters}
            className="w-100"
          >
            Clear Filters
          </Button>
        </Col>
      </Row>
    </div>
  );
};

export default TaskFilters;
