import React from 'react';
import { Row, Col, Card, ProgressBar } from 'react-bootstrap';

const TaskStats = ({ stats }) => {
  // Provide default values if stats is undefined
  const {
    total_tasks = 0,
    completed_tasks = 0,
    pending_tasks = 0,
    completion_rate = 0,
    priority_breakdown = {},
    tasks_created_today = 0
  } = stats || {};

  return (
    <Row className="mb-4">
      <Col md={3}>
        <Card className="text-center bg-primary text-white">
          <Card.Body>
            <h5>Total Tasks</h5>
            <h2>{total_tasks}</h2>
          </Card.Body>
        </Card>
      </Col>
      
      <Col md={3}>
        <Card className="text-center bg-success text-white">
          <Card.Body>
            <h5>Completed</h5>
            <h2>{completed_tasks}</h2>
          </Card.Body>
        </Card>
      </Col>
      
      <Col md={3}>
        <Card className="text-center bg-warning text-white">
          <Card.Body>
            <h5>Pending</h5>
            <h2>{pending_tasks}</h2>
          </Card.Body>
        </Card>
      </Col>
      
      <Col md={3}>
        <Card className="text-center bg-info text-white">
          <Card.Body>
            <h5>Today</h5>
            <h2>{tasks_created_today}</h2>
          </Card.Body>
        </Card>
      </Col>
      
      <Col md={12} className="mt-3">
        <Card>
          <Card.Body>
            <h5>Completion Rate: {completion_rate.toFixed(1)}%</h5>
            <ProgressBar 
              now={completion_rate} 
              variant="success"
              label={`${completion_rate.toFixed(1)}%`}
            />
            
            <Row className="mt-3">
              <Col>
                <small>Priority Breakdown:</small>
                <div>Low: {priority_breakdown['1'] || 0}</div>
                <div>Medium: {priority_breakdown['2'] || 0}</div>
                <div>High: {priority_breakdown['3'] || 0}</div>
              </Col>
            </Row>
          </Card.Body>
        </Card>
      </Col>
    </Row>
  );
};

export default TaskStats;