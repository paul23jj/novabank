-- 06a_mesures.sql : mesures EXPLAIN (ANALYZE, BUFFERS) de 4 requêtes
SET ROLE bank_owner;

-- Q1 : relevé d'un compte, trié par date
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM core.transactions WHERE account_id = 4242 ORDER BY created_at DESC LIMIT 50;

-- Q2 : recherche d'un client par email, sans tenir compte de la casse
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM core.customers WHERE lower(email) = lower('Lucas.Martin1@example.com');

-- Q3 : gros retraits (petite minorité des lignes)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM core.transactions
WHERE tx_type = 'WITHDRAWAL' AND amount >= 5000 AND created_at >= '2026-01-01';

-- Q4 : somme des écritures sur un mois
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount) FROM core.transactions
WHERE created_at >= '2025-03-01' AND created_at < '2025-04-01';
