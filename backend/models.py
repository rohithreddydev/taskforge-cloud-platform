"""
Database models for the Task Manager application
"""
import datetime
from typing import Optional, List, Dict, Any
from typing_extensions import TypedDict

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import Integer, String, Text, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

# Initialize db - this will be imported by app.py
db = SQLAlchemy()

class TaskDict(TypedDict):
    """Type definition for Task dictionary representation"""
    id: int
    title: str
    description: Optional[str]
    completed: bool
    priority: int
    due_date: Optional[str]
    created_at: Optional[str]
    updated_at: Optional[str]
    completed_at: Optional[str]

class Task(db.Model):
    """Task model for the todo application"""
    __tablename__ = 'tasks'
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    priority: Mapped[int] = mapped_column(Integer, default=1)
    due_date: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow, index=True
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow
    )
    completed_at: Mapped[Optional[datetime.datetime]] = mapped_column(DateTime, nullable=True)
    user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey('users.id'), nullable=True)
    
    # Relationships
    user: Mapped[Optional['User']] = relationship('User', back_populates='tasks')
    
    def to_dict(self) -> TaskDict:
        """Convert task to dictionary"""
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'completed': self.completed,
            'priority': self.priority,
            'due_date': self.due_date.isoformat() if self.due_date else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'completed_at': self.completed_at.isoformat() if self.completed_at else None
        }
    
    def __repr__(self) -> str:
        return f'<Task {self.id}: {self.title}>'


class User(db.Model):
    """User model for authentication"""
    __tablename__ = 'users'
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    email: Mapped[str] = mapped_column(String(120), unique=True, nullable=False, index=True)
    password_hash: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=datetime.datetime.utcnow)
    
    # Relationships
    tasks: Mapped[List['Task']] = relationship('Task', back_populates='user', lazy='dynamic')
    
    def __repr__(self) -> str:
        return f'<User {self.username}>'