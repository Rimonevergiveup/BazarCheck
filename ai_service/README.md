# Porokh AI Service

AI service for product recommendations and analysis in the Porokh application.

## Features
- Product analysis and insights
- Personalized recommendations
- Feedback collection for model improvement
- Production-ready with Docker support

## Requirements
- Python 3.11+
- pip
- Docker (optional, for containerized deployment)

## Installation

### Using pip
```bash
# Clone the repository
cd ai_service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the service
python main.py
```

### Using Docker
```bash
# Build the Docker image
docker build -t porokh-ai-service .

# Run the container
docker run -p 8000:8000 porokh-ai-service
```

## API Endpoints

### GET / 
Health check endpoint

### POST /api/v1/analyze-product
Analyze product data and return AI insights

**Request Body:**
```json
{
  "product_id": "prod_001",
  "user_id": "user_001"
}
```

### GET /api/v1/recommendations/{user_id}
Get personalized recommendations for a user

**Query Parameters:**
- `preferences`: JSON string with user preferences

### POST /api/v1/feedback
Submit feedback to improve AI models

## Environment Variables
- `SUPABASE_URL`: Supabase project URL
- `SUPABASE_ANON_KEY`: Supabase anon key
- `DATABASE_URL`: Database connection string
- `REDIS_URL`: Redis cache URL
- `API_PORT`: Port to run the service on

## Development
The service includes mock AI functions that should be replaced with actual AI models in production.

## License
MIT
