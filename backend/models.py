"""
Task Manager Backend API
Database models definition
"""

from app import db
from datetime import datetime, timezone

class Task(db.Model):
    """
    Task model for the todo application
    Represents a task in the system with all its attributes
    """
    __tablename__ = 'tasks'
    
    # Primary key
    id = db.Column(db.Integer, primary_key=True)
    
    # Task details
    title = db.Column(db.String(200), nullable=False, index=True)
    description = db.Column(db.Text)
    completed = db.Column(db.Boolean, default=False, index=True)
    priority = db.Column(db.Integer, default=1)  # 1: Low, 2: Medium, 3: High
    
    # Dates
    due_date = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
    completed_at = db.Column(db.DateTime, nullable=True)
    
    # Foreign key to user (if user system is implemented)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    
    def to_dict(self):
        """
        Convert task object to dictionary for JSON serialization
        """
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'completed': self.completed,
            'priority': self.priority,
            'due_date': self.due_date.isoformat() if self.due_date else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None,
            'user_id': self.user_id
        }
    
    def __repr__(self):
        """
        String representation of the task
        """
        return f'<Task {self.id}: {self.title}>'

class User(db.Model):
    """
    User model for authentication (extend later)
    """
    __tablename__ = 'users'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(128))
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    
    # Relationship with tasks - fixed with foreign key reference
    tasks = db.relationship('Task', backref='user', lazy='dynamic', foreign_keys='Task.user_id')
    
    def to_dict(self):
        """
        Convert user to dictionary
        """
        return {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
    
    def __repr__(self):
        return f'<User {self.id}: {self.username}>'