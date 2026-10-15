-- Campo exclusivo do novo Money no PostgreSQL 17.
-- O PostgreSQL 13 e o backend legado permanecem sem alterações.
ALTER TABLE cliente
    ADD COLUMN IF NOT EXISTS google_maps_link varchar(2048);
