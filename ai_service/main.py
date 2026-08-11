from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uvicorn

app = FastAPI(
    title="Bazaedam AI Service",
    description="AI service for product recommendations and analysis",
    version="1.0.0",
)

class ProductAnalysisRequest(BaseModel):
    product_id: str
    user_id: Optional[str] = None
    context: Optional[dict] = None

class ProductAnalysisResponse(BaseModel):
    product_id: str
    ai_analysis: dict
    confidence_score: float
    recommendations: List[str]

class RecommendationRequest(BaseModel):
    user_id: str
    preferences: Optional[dict] = None

class RecommendationResponse(BaseModel):
    user_id: str
    recommendations: List[dict]
    confidence_score: float

class FeedbackRequest(BaseModel):
    user_id: str
    product_id: str
    rating: Optional[float] = None
    comment: Optional[str] = None
    metadata: Optional[dict] = None

class FeedbackResponse(BaseModel):
    message: str
    status: str

def analyze_product(product_id: str, user_id: Optional[str] = None) -> dict:
    return {
        "category": "Electronics",
        "sentiment": "positive",
        "key_features": ["high performance", "long battery life", "excellent camera"],
        "recommendation_score": 0.95,
    }

def get_recommendations(user_id: str, preferences: Optional[dict] = None) -> List[dict]:
    return [
        {
            "product_id": "prod_001",
            "name": "iPhone 15 Pro",
            "category": "Smartphones",
            "score": 0.98,
            "reason": "Based on your preference for high-performance devices",
        },
        {
            "product_id": "prod_002",
            "name": "MacBook Pro",
            "category": "Laptops",
            "score": 0.92,
            "reason": "Complementary to your smartphone usage pattern",
        },
    ]

@app.get("/")
async def root():
    return {
        "message": "Bazaedam AI Service is running",
        "status": "healthy",
        "version": "1.0.0",
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/api/v1/analyze-product", response_model=ProductAnalysisResponse)
async def analyze_product_endpoint(request: ProductAnalysisRequest):
    try:
        analysis = analyze_product(request.product_id, request.user_id)
        return ProductAnalysisResponse(
            product_id=request.product_id,
            ai_analysis=analysis,
            confidence_score=analysis.get("recommendation_score", 0.8),
            recommendations=[
                f"This product is highly recommended for {analysis.get('category', 'general')} users",
                f"Key features: {', '.join(analysis.get('key_features', []))}",
            ],
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI analysis failed: {str(e)}")

@app.get("/api/v1/recommendations/{user_id}", response_model=RecommendationResponse)
async def get_recommendations_endpoint(user_id: str, preferences: Optional[str] = None):
    try:
        prefs = None
        if preferences:
            import json
            try:
                prefs = json.loads(preferences)
            except json.JSONDecodeError:
                pass

        recommendations = get_recommendations(user_id, prefs)
        return RecommendationResponse(
            user_id=user_id,
            recommendations=recommendations,
            confidence_score=0.85,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Recommendation generation failed: {str(e)}")

@app.post("/api/v1/feedback", response_model=FeedbackResponse)
async def submit_feedback(request: FeedbackRequest):
    try:
        return FeedbackResponse(
            message="Feedback received successfully",
            status="recorded",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to record feedback: {str(e)}")

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
