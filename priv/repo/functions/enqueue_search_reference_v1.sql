() RETURNS TRIGGER AS $$
-- Marks the search records implied by a changed row as dirty.
--
-- One function serves every source table: the trigger definition passes
-- (reference type, column name) pairs as arguments, and the row is read as
-- jsonb so a column can be named at trigger-creation time rather than
-- compiled in. A join table passes two pairs, which is what makes deleting a
-- join row reindex both sides.
--
-- An UPDATE enqueues from OLD *and* NEW, because a row that changes which
-- record it belongs to invalidates two of them. Moving a recording to another
-- book, or relinking a narrator to another person, leaves the record it left
-- quoting a name that is no longer there — and the row that would tell you so
-- is the one being overwritten.
--
-- Deliberately no WHEN clause on the triggers that call this: a list of which
-- columns feed the index would be a second copy of the index's shape, and it
-- would go stale exactly as quietly as the hand-placed calls this replaces.
-- Every write enqueues; the drain is idempotent and rebuilding an unchanged
-- record costs one upsert.
--
-- Postgres collapses identical (channel, payload) notifications within a
-- transaction, so a bulk import delivers one notification however many rows
-- it touches, and delivers it only if the transaction commits.
DECLARE
  rows jsonb[];
  row_json jsonb;
  arg integer;
  ref_id bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    rows := ARRAY[to_jsonb(NEW)];
  ELSIF TG_OP = 'DELETE' THEN
    rows := ARRAY[to_jsonb(OLD)];
  ELSE
    rows := ARRAY[to_jsonb(OLD), to_jsonb(NEW)];
  END IF;

  FOREACH row_json IN ARRAY rows LOOP
    arg := 0;

    WHILE arg < TG_NARGS LOOP
      ref_id := (row_json ->> TG_ARGV[arg + 1])::bigint;

      IF ref_id IS NOT NULL THEN
        INSERT INTO search_index_queue (type, id)
        VALUES (TG_ARGV[arg], ref_id)
        ON CONFLICT DO NOTHING;
      END IF;

      arg := arg + 2;
    END LOOP;
  END LOOP;

  PERFORM pg_notify('search_index_queue', '');

  RETURN NULL;
END
$$ LANGUAGE 'plpgsql';
