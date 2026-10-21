-- 06b_index.sql : 4 index, la taille de chacun, et un index inutile
\set ON_ERROR_STOP on
SET ROLE bank_owner;

DROP INDEX IF EXISTS core.idx_tx_account_date, core.idx_customers_lower_email,
                     core.idx_tx_gros_retraits, core.idx_tx_created_brin;

-- 1. Relevé de compte : filtre par compte, tri par date
CREATE INDEX idx_tx_account_date ON core.transactions (account_id, created_at DESC);
-- 2. Recherche insensible à la casse : la requête doit contenir lower(email)
CREATE INDEX idx_customers_lower_email ON core.customers (lower(email));
-- 3. Index partiel : seulement les gros retraits
CREATE INDEX idx_tx_gros_retraits ON core.transactions (created_at)
    WHERE tx_type = 'WITHDRAWAL' AND amount >= 5000;
-- 4. BRIN : minuscule, efficace car le grand livre est trié par date
CREATE INDEX idx_tx_created_brin ON core.transactions USING brin (created_at);

ANALYZE core.transactions, core.customers;

SELECT indexrelname AS index, pg_size_pretty(pg_relation_size(indexrelid)) AS taille
FROM pg_stat_user_indexes WHERE schemaname = 'core' ORDER BY indexrelname;

-- Un index inutile : 4 valeurs différentes seulement, EXPLAIN préfère lire toute la table
CREATE INDEX idx_tx_type_inutile ON core.transactions (tx_type);
ANALYZE core.transactions;
EXPLAIN (ANALYZE, BUFFERS) SELECT sum(amount) FROM core.transactions WHERE tx_type = 'DEPOSIT';
DROP INDEX core.idx_tx_type_inutile;
