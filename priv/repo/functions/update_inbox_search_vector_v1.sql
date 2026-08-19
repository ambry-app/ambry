() RETURNS TRIGGER AS $$
-- An inbox item is findable by its path and by what the draft says it is.
--
-- The path is weight A because it is the item's identity — it is what the
-- queue shows and what an operator recognises. `search_text` is weight B: it
-- is a *proposal*, sometimes a provider's guess, and should not outrank the
-- name of the thing on disk.
--
-- Only the vector is computed here. `search_text` itself is written from
-- Elixir, in `Ambry.Inbox.InboxItem.put_draft/2`, because the draft is a deep
-- embedded structure and a trigger digging through that JSON would be a
-- second copy of its shape — the thing dropping `search_index.dependencies`
-- was about.
BEGIN
  NEW.search_vector =
    setweight(to_tsvector('ambry_english', COALESCE(NEW.path, '')), 'A') ||
    setweight(to_tsvector('ambry_english', COALESCE(NEW.search_text, '')), 'B');

  RETURN NEW;
END
$$ LANGUAGE 'plpgsql';
