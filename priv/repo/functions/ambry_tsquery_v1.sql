(phrase text, joiner text, partial boolean) RETURNS tsquery AS $$
-- One tsquery, built the way the caller asked for it.
--
-- Postgres does every bit of the parsing: tokenizing, stripping punctuation,
-- folding accents, stemming, dropping stop words. All this does is rewrite
-- the operator between the lexemes it hands back, and optionally open the
-- last one to a prefix match. That is the whole reason the hand-rolled
-- tokenizer and its stopword list can go — they were reimplementing
-- `plainto_tsquery`, badly and unindexably.
--
-- Rewriting through the text form is safe because no lexeme can contain
-- ' & ': an ampersand is punctuation, so it never survives tokenization into
-- a lexeme in the first place.
--
-- Returns NULL for a phrase with nothing searchable in it — an empty box, or
-- one holding only stop words. A caller shows the first page rather than
-- nothing, which is what somebody who has just clicked into a search box
-- wants to see.
DECLARE
  base tsquery;
  rewritten text;
BEGIN
  base := plainto_tsquery('ambry_english', phrase);
  rewritten := base::text;

  IF rewritten = '' THEN
    RETURN NULL;
  END IF;

  IF joiner = 'any' THEN
    rewritten := replace(rewritten, ' & ', ' | ');
  END IF;

  IF partial THEN
    rewritten := rewritten || ':*';
  END IF;

  RETURN rewritten::tsquery;
END
$$ LANGUAGE 'plpgsql' IMMUTABLE;
