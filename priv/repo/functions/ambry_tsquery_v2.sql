(phrase text, joiner text, partial boolean) RETURNS tsquery AS $$
-- One tsquery, asked of both analyses of the text.
--
-- `ambry_english` stems and drops stop words; `ambry_simple` does neither.
-- Each is wrong on its own for a catalogue of proper nouns:
--
--   typed        target                english   simple
--   kings        King Rat              yes       no      (stemming earns its keep)
--   memories     Children of Memory    yes       no
--   don          Don Quixote           NO        yes     ("don" is in english.stop, from "don't")
--   will         Will Wight            NO        yes
--
-- So the record is indexed under both and the query is asked under both,
-- OR'd together — the multi-field technique every real search engine uses,
-- where a field is analyzed several ways and the best match wins. A branch
-- that finds nothing costs nothing, which is the same reason `:any` exists.
--
-- Note the OR is between whole branches, not between terms: `:all` means
-- every term matched *under one analysis*, never a mix of the two.
--
-- Returns NULL when neither analysis finds a lexeme — an empty box, or
-- nothing but punctuation. A caller shows the first page for the first and
-- nothing for the second, which are different questions.
DECLARE
  english text;
  simple text;
BEGIN
  english := plainto_tsquery('ambry_english', phrase)::text;
  simple := plainto_tsquery('ambry_simple', phrase)::text;

  IF joiner = 'any' THEN
    english := replace(english, ' & ', ' | ');
    simple := replace(simple, ' & ', ' | ');
  END IF;

  IF partial THEN
    IF english <> '' THEN english := english || ':*'; END IF;
    IF simple <> '' THEN simple := simple || ':*'; END IF;
  END IF;

  IF english = '' AND simple = '' THEN
    RETURN NULL;
  ELSIF english = '' THEN
    RETURN simple::tsquery;
  ELSIF simple = '' THEN
    RETURN english::tsquery;
  ELSE
    RETURN english::tsquery || simple::tsquery;
  END IF;
END
$$ LANGUAGE 'plpgsql' IMMUTABLE;
