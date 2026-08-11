# Bazaedam App Reference Guide

## 📁 File Structure Reference

### Root Directory (e:/bazaedam/)
- `Recomend.txt`: Original requirements and recommendations
- `supabase_schema.sql`: Supabase database schema
- `ARCHITECTURE.md`: Complete architecture documentation
- `IMPLEMENTATION_SUMMARY.md`: Implementation status summary
- `STATUS.md`: Current project status
- `PROJECT_CONFIG.md`: Project configuration
- `MANIFEST.md`: Project purpose and scope
- `CHECKLIST.md`: Implementation checklist
- `SUMMARY.md`: Executive summary
- `ROADMAP.md`: Development timeline
- `TECHNICAL_SPEC.md`: Technical specifications
- `OVERVIEW.md`: Project overview
- `STATUS_SUMMARY.md`: Status summary
- `QUICK_SUMMARY.md`: Quick summary
- `ONE_PAGE_SUMMARY.md`: One-page summary
- `REFERENCE_GUIDE.md`: This file
- `package.json`: Project management scripts
- `.gitignore`: Git ignore configuration
- `.env.example`: Environment variables template

### Flutter App (e:/bazaedam/bazaedam_app/)
- `lib/`: Dart source code
  - `main.dart`: Application entry point
  - `providers.dart`: Riverpod providers
  - `models/`: Data models (Division, Category, Product)
  - `repositories/`: Data access layer (Supabase repository)
  - `services/`: Business logic services (Auth service)
  - `screens/`: UI screens (Home screen)
- `pubspec.yaml`: Dependencies and configuration
- `README.md`: Flutter app documentation
- `.gitignore`: Flutter-specific git ignore

### Python AI Service (e:/bazaedam/ai_service/)
- `main.py`: FastAPI application
- `requirements.txt`: Python dependencies
- `Dockerfile`: Docker configuration
- `.env`: Environment configuration
- `README.md`: AI service documentation
- `.gitignore`: Python-specific git ignore

## 🛠️ Key Configuration Files

### Supabase Configuration
- `supabase_schema.sql`: Database schema with RLS policies
- `bazaedam_app/lib/providers.dart`: Supabase client configuration

### Flutter Configuration
- `bazaedam_app/pubspec.yaml`: Dependencies and configuration
- `bazaedam_app/lib/main.dart`: Application entry point

### Python AI Configuration
- `ai_service/main.py`: FastAPI application
- `ai_service/requirements.txt`: Python dependencies
- `ai_service/Dockerfile`: Container configuration

## 🚀 Getting Started Commands

### Setup
```bash
npm run setup
```

### Run Flutter App
```bash
npm run start:flutter
# or
cd bazaedam_app && flutter run
```

### Run Python AI Service
```bash
npm run start:ai
# or
cd ai_service && python main.py
```

### Build Flutter App
```bash
npm run build:flutter
# or
cd bazaedam_app && flutter build apk
```

### Build Python AI Service
```bash
npm run build:ai
# or
cd ai_service && docker build -t bazaedam-ai-service .
```

## 📝 Documentation Overview

| Document | Purpose |
|----------|---------|
| `ARCHITECTURE.md` | Complete architecture documentation |
| `IMPLEMENTATION_SUMMARY.md` | Implementation status summary |
| `STATUS.md` | Current project status |
| `PROJECT_CONFIG.md` | Project configuration |
| `MANIFEST.md` | Project purpose and scope |
| `CHECKLIST.md` | Implementation checklist |
| `SUMMARY.md` | Executive summary |
| `ROADMAP.md` | Development timeline |
| `TECHNICAL_SPEC.md` | Technical specifications |
| `OVERVIEW.md` | Project overview |
| `STATUS_SUMMARY.md` | Status summary |
| `QUICK_SUMMARY.md` | Quick summary |
| `ONE_PAGE_SUMMARY.md` | One-page summary |
| `REFERENCE_GUIDE.md` | This reference guide |

## 🤝 Support
For questions or assistance, please contact the Bazaedam Team.

## 📜 License
MIT
