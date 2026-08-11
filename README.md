# Bazaedam App

Complete production architecture for Flutter + Supabase + Python AI application.

## Project Structure
```
e:/bazaedam/
├── Recomend.txt          # Original requirements and recommendations
├── supabase_schema.sql   # Supabase database schema
├── ARCHITECTURE.md       # Complete architecture documentation
├── package.json          # Project management scripts
├── bazaedam_app/         # Flutter frontend application
│   ├── lib/              # Dart source code
│   ├── pubspec.yaml      # Dependencies and configuration
│   └── ...               # Other Flutter files
└── ai_service/           # Python AI service
    ├── main.py           # FastAPI application
    ├── requirements.txt  # Python dependencies
    ├── Dockerfile        # Docker configuration
    └── ...               # Other Python files
```

## Getting Started

### Prerequisites
- Flutter SDK (v3.10+)
- Dart SDK
- Python 3.11+
- Node.js (for package.json scripts)

### Setup
1. **Install dependencies**:
   ```bash
   npm run setup
   ```

2. **Configure Supabase**:
   - Create a Supabase project at https://supabase.com
   - Run the SQL schema from `supabase_schema.sql` in your Supabase database
   - Replace the Supabase URL and keys in `bazaedam_app/lib/providers.dart`

3. **Run the applications**:
   - Start Flutter app: `npm run start:flutter`
   - Start AI service: `npm run start:ai`

## Architecture Highlights
- ✅ **Dynamic Data Loading**: All divisions, products, categories loaded from Supabase
- ✅ **Separation of Concerns**: Clear separation between frontend, database, and AI services
- ✅ **Scalability**: Architecture designed to handle growth in users and data
- ✅ **Production-Ready**: Includes security, monitoring, and deployment considerations

## License
MIT
