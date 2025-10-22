# HNG DevOps Stage 1 - Automated Deployment

This is a simple Node.js application created for the HNG DevOps Intern Stage 1 task. It demonstrates automated deployment using Docker and Bash scripting.

## Project Overview

A lightweight Express.js web server that provides multiple endpoints for testing deployment and health checks.

## Features

- RESTful API endpoints
- Health check functionality
- Docker containerization
- Docker Compose support
- Graceful shutdown handling
- Environment-based configuration

## Endpoints

- `GET /` - Root endpoint with server information
- `GET /health` - Health check endpoint
- `GET /api` - API information and available endpoints
- `GET /info` - Deployment and container information

## Prerequisites

- Node.js 18+ (for local development)
- Docker (for containerized deployment)
- Docker Compose (optional)

## Local Development

### Install Dependencies
```bash
npm install
```

### Run Locally
```bash
npm start
```

The server will start on `http://localhost:3000`

## Docker Deployment

### Build and Run with Docker
```bash
# Build the image
docker build -t hng-devops-app .

# Run the container
docker run -d -p 3000:3000 --name hng-app hng-devops-app
```

### Using Docker Compose
```bash
# Start the application
docker-compose up -d

# Stop the application
docker-compose down
```

## Testing the Application

### Test Locally
```bash
curl http://localhost:3000
curl http://localhost:3000/health
curl http://localhost:3000/api
curl http://localhost:3000/info
```

### Test on Remote Server
```bash
curl http://YOUR_SERVER_IP
curl http://YOUR_SERVER_IP/health
```

## Automated Deployment

This application is designed to be deployed using the automated Bash scripts:

1. `prepare_deploy.sh` - Handles deployment to remote server
2. `validate_deploy.sh` - Validates the deployment

### Deployment Steps

1. Clone this repository
2. Run the deployment script:
   ```bash
   ./prepare_deploy.sh
   ```
3. Validate the deployment:
   ```bash
   ./validate_deploy.sh
   ```

## Environment Variables

- `PORT` - Application port (default: 3000)
- `NODE_ENV` - Environment mode (default: production)

## Health Check

The application includes a built-in health check that runs every 30 seconds. It verifies that the `/health` endpoint responds with a 200 status code.

## Project Structure

```
.
├── Dockerfile              # Docker configuration
├── docker-compose.yml      # Docker Compose configuration
├── server.js              # Main application file
├── healthcheck.js         # Health check script
├── package.json           # Node.js dependencies
└── README.md             # This file
```

## Author

okwujudith@gmail.com

## License

MIT

## HNG Internship

This project is part of the HNG DevOps Internship program.
Learn more at: https://hng.tech/internship
