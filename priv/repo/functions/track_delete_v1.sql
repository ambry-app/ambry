() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO deletions(type, record_id, deleted_at)
    VALUES (TG_ARGV[0], old.id, current_timestamp)
    ON CONFLICT DO NOTHING;
    RETURN old;
  END IF;
END;
$$ LANGUAGE plpgsql;