() RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector = setweight(to_tsvector('ambry_english', COALESCE(NEW.primary, '')), 'A')
                   || setweight(to_tsvector('ambry_english', COALESCE(NEW.secondary, '')), 'B')
                   || setweight(to_tsvector('ambry_english', COALESCE(NEW.tertiary, '')), 'C');
  RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
