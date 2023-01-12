() RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector = setweight(to_tsvector('pg_catalog.english', COALESCE(NEW.primary, '')), 'A')
                   || setweight(to_tsvector('pg_catalog.english', COALESCE(NEW.secondary, '')), 'B')
                   || setweight(to_tsvector('pg_catalog.english', COALESCE(NEW.tertiary, '')), 'C');
  RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
