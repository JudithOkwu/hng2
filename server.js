
const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware to parse JSON
app.use(express.json());

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'HNG DevOps Stage 1 - Automated Deployment',
    status: 'success',
    timestamp: new Date().toISOString(),
    server: {
      hostname: os.hostname(),
      platform: os.platform(),
      uptime: process.uptime(),
    }
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// API endpoint
app.get('/api', (req, res) => {
  res.json({
    message: 'API is working',
    version: '1.0.0',
    endpoints: [
      { path: '/', method: 'GET', description: 'Root endpoint' },
      { path: '/health', method: 'GET', description: 'Health check' },
      { path: '/api', method: 'GET', description: 'API information' },
      { path: '/info', method: 'GET', description: 'Deployment information' }
    ]
  });
});

// Deployment info endpoint
app.get('/info', (req, res) => {
  res.json({
    project: 'HNG DevOps Intern Stage 1',
    task: 'Automated Deployment with Bash Script',
    deployed: true,
    container: {
      running: true,
      environment: process.env.NODE_ENV || 'production'
    },
    server: {
      hostname: os.hostname(),
      platform: os.platform(),
      nodeVersion: process.version
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Route not found',
    path: req.path
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal server error',
    message: err.message
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server is running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'production'}`);
  console.log(`Hostname: ${os.hostname()}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT signal received: closing HTTP server');
  process.exit(0);
});