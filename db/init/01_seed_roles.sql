INSERT INTO role(name, admin) VALUES
  ('admin', TRUE),
  ('customer', FALSE)
ON CONFLICT (name) DO NOTHING;