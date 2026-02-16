import axios from 'axios';

// Get API URL from environment or use default
const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000/api';

// Create axios instance with base configuration
const api = axios.create({
  baseURL: API_URL,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  }
});

// Request interceptor
api.interceptors.request.use(
  config => {
    // You can add auth tokens here
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    
    // Log requests in development
    if (process.env.NODE_ENV === 'development') {
      console.log(`API Request: ${config.method?.toUpperCase()} ${config.url}`, config);
    }
    
    return config;
  },
  error => {
    return Promise.reject(error);
  }
);

// Response interceptor
api.interceptors.response.use(
  response => {
    // Log responses in development
    if (process.env.NODE_ENV === 'development') {
      console.log(`API Response: ${response.status}`, response.data);
    }
    return response;
  },
  error => {
    // Handle errors globally
    if (error.response) {
      // Server responded with error status
      console.error('API Error:', error.response.status, error.response.data);
      
      // Handle specific status codes
      switch (error.response.status) {
        case 401:
          console.log('Unauthorized access');
          break;
        case 403:
          console.log('Forbidden access');
          break;
        case 404:
          console.log('Resource not found');
          break;
        case 429:
          console.log('Rate limit exceeded');
          break;
        case 500:
          console.log('Server error');
          break;
        default:
          console.log('Unknown error');
      }
    } else if (error.request) {
      // Request was made but no response
      console.error('No response from server:', error.request);
    } else {
      // Something else happened
      console.error('Error:', error.message);
    }
    
    return Promise.reject(error);
  }
);

export default api;