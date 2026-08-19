() RETURNS TRIGGER AS $$
-- Both analyses of every column, at the column's own weight. See
-- `ambry_tsquery` for why there are two.
--
-- Lexemes the two agree on merge rather than doubling — "way" analyzes to
-- "way" either way — so the vector grows by the words the stemmer changes,
-- not by half.
BEGIN
  NEW.search_vector =
    setweight(
      to_tsvector('ambry_english', COALESCE(NEW.primary, '')) ||
      to_tsvector('ambry_simple', COALESCE(NEW.primary, '')), 'A') ||
    setweight(
      to_tsvector('ambry_english', COALESCE(NEW.secondary, '')) ||
      to_tsvector('ambry_simple', COALESCE(NEW.secondary, '')), 'B') ||
    setweight(
      to_tsvector('ambry_english', COALESCE(NEW.tertiary, '')) ||
      to_tsvector('ambry_simple', COALESCE(NEW.tertiary, '')), 'C');

  RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
