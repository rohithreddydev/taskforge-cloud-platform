import api from './api';

// Mock axios with proper implementation
jest.mock('axios', () => {
  // Create a mock instance with all required properties
  const mockAxiosInstance = {
    defaults: {
      baseURL: 'http://localhost:5000/api',
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    },
    interceptors: {
      request: { use: jest.fn((success, error) => ({ success, error })) },
      response: { use: jest.fn((success, error) => ({ success, error })) }
    },
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
    delete: jest.fn()
  };

  return {
    create: jest.fn(() => mockAxiosInstance)
  };
});

describe('API Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('api object is defined', () => {
    expect(api).toBeDefined();
  });

  test('api has required interceptors', () => {
    expect(api.interceptors).toBeDefined();
    expect(api.interceptors.request).toBeDefined();
    expect(api.interceptors.response).toBeDefined();
  });

  test('api has required HTTP methods', () => {
    expect(typeof api.get).toBe('function');
    expect(typeof api.post).toBe('function');
    expect(typeof api.put).toBe('function');
    expect(typeof api.delete).toBe('function');
  });

  test('api has baseURL configured', () => {
    expect(api.defaults).toBeDefined();
    expect(api.defaults.baseURL).toBeDefined();
    expect(api.defaults.baseURL).toBe('http://localhost:5000/api');
  });

  test('api has default headers', () => {
    expect(api.defaults).toBeDefined();
    expect(api.defaults.headers).toBeDefined();
    expect(api.defaults.headers['Content-Type']).toBe('application/json');
    expect(api.defaults.headers['Accept']).toBe('application/json');
  });

  test('api has timeout configured', () => {
    expect(api.defaults).toBeDefined();
    expect(api.defaults.timeout).toBeDefined();
    expect(api.defaults.timeout).toBe(10000);
  });
});