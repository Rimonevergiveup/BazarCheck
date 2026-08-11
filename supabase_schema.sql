-- Supabase Database Schema
-- Created for Flutter + Supabase + Python AI Architecture

-- Create divisions table
CREATE TABLE IF NOT EXISTS divisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on divisions table
ALTER TABLE divisions ENABLE ROW LEVEL SECURITY;

-- Create policy for divisions (public read, authenticated insert/update)
CREATE POLICY "Enable read access for all users" ON divisions
  FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users only" ON divisions
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Enable update for authenticated users only" ON divisions
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  division_id UUID REFERENCES divisions(id) ON DELETE CASCADE,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on categories table
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

-- Create policy for categories (public read, authenticated insert/update)
CREATE POLICY "Enable read access for all users" ON categories
  FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users only" ON categories
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Enable update for authenticated users only" ON categories
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Create products table
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  category_id UUID REFERENCES categories(id) ON DELETE CASCADE,
  description TEXT,
  price NUMERIC(10,2),
  image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on products table
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Create policy for products (public read, authenticated insert/update)
CREATE POLICY "Enable read access for all users" ON products
  FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users only" ON products
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Enable update for authenticated users only" ON products
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Create ai_results table
CREATE TABLE IF NOT EXISTS ai_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  ai_analysis JSONB NOT NULL,
  confidence_score NUMERIC(3,2) CHECK (confidence_score BETWEEN 0 AND 1),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on ai_results table
ALTER TABLE ai_results ENABLE ROW LEVEL SECURITY;

-- Create policy for ai_results (user can only read their own results)
CREATE POLICY "Enable read access for owner" ON ai_results
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Enable insert for authenticated users only" ON ai_results
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_categories_division_id ON categories(division_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_user_id ON ai_results(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_results_product_id ON ai_results(product_id);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for divisions table
CREATE TRIGGER set_timestamp_divisions 
  BEFORE UPDATE ON divisions 
  FOR EACH ROW 
  EXECUTE FUNCTION trigger_set_timestamp();

-- Trigger for categories table
CREATE TRIGGER set_timestamp_categories 
  BEFORE UPDATE ON categories 
  FOR EACH ROW 
  EXECUTE FUNCTION trigger_set_timestamp();

-- Trigger for products table
CREATE TRIGGER set_timestamp_products 
  BEFORE UPDATE ON products 
  FOR EACH ROW 
  EXECUTE FUNCTION trigger_set_timestamp();

-- Trigger for ai_results table
CREATE TRIGGER set_timestamp_ai_results 
  BEFORE UPDATE ON ai_results 
  FOR EACH ROW 
  EXECUTE FUNCTION trigger_set_timestamp();

-- Insert sample data for testing
INSERT INTO divisions (name, description) VALUES 
  ('Electronics', 'Electronic devices and gadgets'),
  ('Clothing', 'Apparel and fashion items'),
  ('Home & Kitchen', 'Household items and kitchenware');

INSERT INTO categories (name, division_id, description) VALUES 
  ('Smartphones', (SELECT id FROM divisions WHERE name = 'Electronics'), 'Mobile phones and smartphones'),
  ('Laptops', (SELECT id FROM divisions WHERE name = 'Electronics'), 'Portable computers'),
  ('T-Shirts', (SELECT id FROM divisions WHERE name = 'Clothing'), 'Casual t-shirts'),
  ('Jeans', (SELECT id FROM divisions WHERE name = 'Clothing'), 'Denim pants'),
  ('Cookware', (SELECT id FROM divisions WHERE name = 'Home & Kitchen'), 'Pots, pans, and cooking utensils'),
  ('Kitchen Appliances', (SELECT id FROM divisions WHERE name = 'Home & Kitchen'), 'Electric kitchen appliances');

INSERT INTO products (name, category_id, description, price, image_url) VALUES 
  ('iPhone 15 Pro', (SELECT id FROM categories WHERE name = 'Smartphones'), 'Latest Apple smartphone', 999.99, 'https://example.com/iphone15.jpg'),
  ('MacBook Pro', (SELECT id FROM categories WHERE name = 'Laptops'), 'Professional laptop', 1999.99, 'https://example.com/macbook.jpg'),
  ('Cotton T-Shirt', (SELECT id FROM categories WHERE name = 'T-Shirts'), '100% cotton t-shirt', 24.99, 'https://example.com/tshirt.jpg'),
  ('Slim Fit Jeans', (SELECT id FROM categories WHERE name = 'Jeans'), 'Comfortable denim jeans', 79.99, 'https://example.com/jeans.jpg');
