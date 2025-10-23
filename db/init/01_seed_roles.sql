INSERT INTO role(name, admin) VALUES ('User',false),('Admin',true)
ON CONFLICT DO NOTHING;
