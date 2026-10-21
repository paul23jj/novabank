-- 05_vues.sql : une vue qui masque, une vue modifiable avec limite, une vue enregistrée
-- À lancer en tant que postgres, dans bankdb. Les vues appartiennent à bank_owner.
\set ON_ERROR_STOP on
SET ROLE bank_owner;

-- 1. Vue qui CACHE des données (support) : email, nom et téléphone masqués
CREATE VIEW core.v_customers_support WITH (security_barrier = true) AS
SELECT customer_id,
       first_name,
       left(last_name, 1) || '.'                      AS last_name,
       left(email, 2) || '***' || substr(email, strpos(email, '@')) AS email,
       '******' || right(phone, 2)                    AS phone,
       kyc_status
FROM core.customers;

-- 2. Vue MODIFIABLE avec limite : le support change le statut d'un compte,
--    mais ne peut pas le passer à CLOSED (CHECK OPTION)
CREATE VIEW core.v_accounts_support AS
SELECT account_id, customer_id, iban, account_type, status, balance
FROM core.accounts
WHERE status IN ('ACTIVE', 'FROZEN')
WITH LOCAL CHECK OPTION;

-- 3. Vue ENREGISTRÉE (matérialisée) : statistiques des comptes, figées jusqu'au REFRESH
CREATE MATERIALIZED VIEW core.mv_stats_comptes AS
SELECT account_type, status, count(*) AS nb_comptes, sum(balance) AS solde_total
FROM core.accounts
GROUP BY account_type, status;
CREATE UNIQUE INDEX uq_mv_stats_comptes ON core.mv_stats_comptes (account_type, status);

-- Droits : le support ne voit que les vues, et ne modifie que le statut
GRANT SELECT ON core.v_customers_support TO grp_support;
GRANT SELECT, UPDATE (status) ON core.v_accounts_support TO grp_support;
GRANT SELECT ON core.mv_stats_comptes TO grp_analyste, grp_auditeur;
