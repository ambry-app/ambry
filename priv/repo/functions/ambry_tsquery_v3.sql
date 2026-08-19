(phrase text, joiner text, partial boolean) RETURNS tsquery AS $$
-- One tsquery, asked of both analyses of the text — `ambry_english`, which
-- stems and drops stop words, and `ambry_simple`, which does neither. Each is
-- wrong alone for a catalogue of proper nouns:
--
--   typed        target                english   simple
--   kings        King Rat              yes       no      (stemming earns its keep)
--   memories     Children of Memory    yes       no
--   don          Don Quixote           NO        yes     ("don" is in english.stop)
--   will         Will Wight            NO        yes
--
-- So the record is indexed under both and the query is asked under both,
-- OR'd. The OR is between whole branches, not between terms: `:all` means
-- every term matched *under one analysis*, never a mix of the two.
--
-- Returns NULL when neither analysis finds a lexeme — an empty box, or
-- nothing but punctuation. A caller shows the first page for the first and
-- nothing for the second, which are different questions.
--
-- Two things v2 got wrong, both found by an operator who could not find his
-- own books (2026-08-19):
--
-- 1. A stop word is not a search term. `ambry_simple` keeps stop words so
--    that somebody named Don is findable, but that only ever meant "when the
--    phrase is *nothing but* stop words". Carried alongside real terms under
--    `:any` they OR in most of the library ("the end of all things" reached
--    239 of 419 books) and, worse, `ts_rank_cd` counts them as evidence.
--    So: a word is a search term iff the english analyzer keeps it, and the
--    whole phrase falls back to the literal words only when none survive —
--    which is, and always was, the only case the simple branch's stop words
--    were there to serve.
--
-- 2. The prefix belongs to what was typed, not to its stem. v2 stemmed and
--    then appended `:*`, so "mars" became `'mar':*` and prefix-matched
--    Martha, Marlon, Markson, Marin, Martin, Marsters, Marissa, Maryam.
--    The unstemmed branch already carries the prefix property correctly, so
--    the stemmed branch does not get `:*` at all.
DECLARE
  words     text[];
  terms     text[];
  stems     text[];
  w         text;
  stem      text;
  op        text;
  english   text;
  simple    text;
BEGIN
  SELECT array_agg(lexeme ORDER BY positions[1])
    INTO words
    FROM unnest(to_tsvector('ambry_simple', phrase));

  IF words IS NULL THEN
    RETURN NULL;
  END IF;

  terms := '{}';
  stems := '{}';

  FOREACH w IN ARRAY words LOOP
    stem := NULL;
    SELECT lexeme INTO stem FROM unnest(to_tsvector('ambry_english', w)) LIMIT 1;
    IF stem IS NOT NULL THEN
      terms := terms || w;
      stems := stems || stem;
    END IF;
  END LOOP;

  -- Nothing but stop words: then they are the search. "Don", "Will".
  IF array_length(terms, 1) IS NULL THEN
    terms := words;
    stems := '{}';
  END IF;

  op := CASE WHEN joiner = 'any' THEN ' | ' ELSE ' & ' END;

  -- The unstemmed branch, last term opened to a prefix when asked.
  SELECT array_to_string(array_agg(
           CASE WHEN partial AND i = array_length(terms, 1)
                THEN quote_literal(terms[i]) || ':*'
                ELSE quote_literal(terms[i])
           END ORDER BY i), op)
    INTO simple
    FROM generate_subscripts(terms, 1) AS i;

  -- The stemmed branch. No prefix: a stem is not a prefix of what was typed.
  SELECT array_to_string(array_agg(quote_literal(stems[i]) ORDER BY i), op)
    INTO english
    FROM generate_subscripts(stems, 1) AS i;

  IF english IS NULL OR english = '' THEN
    RETURN simple::tsquery;
  ELSIF simple IS NULL OR simple = '' THEN
    RETURN english::tsquery;
  ELSE
    RETURN english::tsquery || simple::tsquery;
  END IF;
END
$$ LANGUAGE 'plpgsql' IMMUTABLE;
