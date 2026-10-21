-- 91_tests_base.sql : contraintes (E2), droits (E3), vues (E4)
-- Pour chaque règle : un test qui réussit et un test refusé
\set ON_ERROR_STOP off
\set ECHO queries
\pset pager off

\echo '=== E2 : contraintes ==='
SET ROLE bank_owner;
INSERT INTO core.customers(first_name,last_name,email,birth_date,kyc_status) VALUES ('Test','Valide','test.valide@example.com','1990-01-01','VERIFIED');
INSERT INTO core.customers(first_name,last_name,email,birth_date) VALUES ('A','B','pas-un-email','1990-01-01');
INSERT INTO core.customers(first_name,last_name,email,birth_date) VALUES ('A','B','test.valide@example.com','1990-01-01');
INSERT INTO core.customers(first_name,last_name,email,birth_date) VALUES ('A','B','mineur@example.com',(current_date - INTERVAL '10 years')::date);
UPDATE core.accounts SET balance = -1 WHERE account_id = 1;
INSERT INTO core.accounts(customer_id, iban) SELECT 1, iban FROM core.accounts WHERE account_id = 1;
INSERT INTO core.transfers(from_account_id,to_account_id,amount) VALUES (1,1,10);
INSERT INTO core.transfers(from_account_id,to_account_id,amount) VALUES (1,2,-5);
RESET ROLE;

\echo '=== E3 : droits (OK ou permission denied) ==='
SET ROLE analyste_1;
SELECT count(*) FROM core.accounts;
SELECT birth_date FROM core.customers LIMIT 1;
SELECT email FROM core.customers LIMIT 1;
UPDATE core.accounts SET balance = 0 WHERE account_id = 1;
RESET ROLE;
SET ROLE support_1;
SELECT * FROM core.customers LIMIT 1;
RESET ROLE;
SET ROLE bank_app;
SELECT * FROM core.accounts LIMIT 1;
RESET ROLE;
SET ROLE auditeur_1;
SELECT count(*) FROM audit.audit_log;
DELETE FROM audit.audit_log;
RESET ROLE;

\echo '=== E4 : vues ==='
SET ROLE support_1;
SELECT * FROM core.v_customers_support LIMIT 3;
UPDATE core.v_accounts_support SET status = 'FROZEN' WHERE account_id = 2;
UPDATE core.v_accounts_support SET status = 'CLOSED' WHERE account_id = 2;
UPDATE core.v_accounts_support SET balance = 0 WHERE account_id = 2;
RESET ROLE;
SELECT account_type, status, nb_comptes FROM core.mv_stats_comptes ORDER BY 1,2;
SELECT account_type, status, count(*) FROM core.accounts GROUP BY 1,2 ORDER BY 1,2;
REFRESH MATERIALIZED VIEW CONCURRENTLY core.mv_stats_comptes;
SELECT account_type, status, nb_comptes FROM core.mv_stats_comptes ORDER BY 1,2;
UPDATE core.accounts SET status = 'ACTIVE' WHERE account_id = 2;
