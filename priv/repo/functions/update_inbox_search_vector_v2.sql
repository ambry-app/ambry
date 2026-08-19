() RETURNS TRIGGER AS $$
-- Both analyses, as `search_index` does. Path is weight A because it is the
-- item's identity; the draft is a proposal and should not outrank the name
-- of the thing on disk.
BEGIN
  NEW.search_vector =
    setweight(
      to_tsvector('ambry_english', COALESCE(NEW.path, '')) ||
      to_tsvector('ambry_simple', COALESCE(NEW.path, '')), 'A') ||
    setweight(
      to_tsvector('ambry_english', COALESCE(NEW.search_text, '')) ||
      to_tsvector('ambry_simple', COALESCE(NEW.search_text, '')), 'B');

  RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
