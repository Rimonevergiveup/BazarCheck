# Porokh App

Flutter application with Supabase backend and Python AI service.

## Architecture
- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL + Auth + Storage)
- **AI Service**: Python FastAPI

## Features
- Dynamic data loading from Supabase (no hardcoded values)
- User authentication with Supabase Auth
- Product recommendations powered by AI
- Real-time data sync
- Scalable architecture

## Setup

### Prerequisites
- Flutter SDK
- Dart SDK
- Python 3.11+

### Flutter Setup
```bash
# Clone the repository
cd porokh_app

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Supabase Setup
1. Create a Supabase project at https://supabase.com
2. Replace the Supabase URL and anon key in `lib/providers.dart`
3. Run the SQL schema from `supabase_schema.sql` in your Supabase database

### Python AI Service Setup
```bash
# Clone the AI service
cd ../ai_service

# Install dependencies
pip install -r requirements.txt

# Run the service
python main.py
```

## Project Structure
- `lib/`: Flutter application code
- `lib/models/`: Data models
- `lib/repositories/`: Data access layer
- `lib/services/`: Business logic services
- `lib/screens/`: UI screens
- `lib/providers.dart`: Riverpod providers

## License
MIT
