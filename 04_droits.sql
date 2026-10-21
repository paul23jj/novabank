-- 04_droits.sql : 4 profils avec le minimum de droits
-- À lancer en tant que postgres, dans bankdb. Ne se lance qu'une fois sur une base neuve
-- (le script "tout refaire" repart de zéro).
\set ON_ERROR_STOP on

-- 1. Groupes (sans connexion) et comptes (avec connexion, membres d'un groupe)
CREATE ROLE grp_analyste NOLOGIN;
CREATE ROLE grp_support  NOLOGIN;
CREATE ROLE grp_auditeur NOLOGIN;
CREATE ROLE analyste_1 LOGIN IN ROLE grp_analyste;
CREATE ROLE support_1  LOGIN IN ROLE grp_support;
CREATE ROLE auditeur_1 LOGIN IN ROLE grp_auditeur;
CREATE ROLE bank_app   LOGIN;

-- 2. On ferme les portes ouvertes à "tout le monde" (PUBLIC)
REVOKE ALL ON DATABASE bankdb FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA core, audit FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- 3. Porte 1 : se connecter à la base
GRANT CONNECT ON DATABASE bankdb TO grp_analyste, grp_support, grp_auditeur, bank_app;

-- 4. Porte 2 : entrer dans les schémas
GRANT USAGE ON SCHEMA core TO grp_analyste, grp_support, grp_auditeur, bank_app;
GRANT USAGE ON SCHEMA audit TO grp_auditeur;

-- 5. Porte 3 : les droits sur les objets
-- Analyste : tout sauf les données personnelles des clients (droit par colonne)
GRANT SELECT (customer_id, birth_date, kyc_status, risk_level, created_at)
    ON core.customers TO grp_analyste;
GRANT SELECT ON core.accounts, core.transfers, core.transactions, core.fraud_alerts
    TO grp_analyste;
-- Auditeur : lecture seule des écritures, des alertes et du journal
GRANT SELECT ON core.transactions, core.transfers, core.fraud_alerts, audit.audit_log
    TO grp_auditeur;
-- Support : rien ici, il utilise des vues (05_vues.sql)
-- Appli   : rien ici, elle appelle des procédures (07_procedures.sql)

-- 6. Garde-fou : durée maximale d'une requête (réglage du compte, pas du groupe)
ALTER ROLE analyste_1 SET statement_timeout = '60s';
ALTER ROLE support_1  SET statement_timeout = '10s';
ALTER ROLE auditeur_1 SET statement_timeout = '60s';

-- 7. Matrice de preuve : qui peut faire quoi sur chaque table
SELECT r AS role, t AS table_name,
       has_table_privilege(r, t, 'SELECT') AS "select",
       has_table_privilege(r, t, 'INSERT') AS "insert",
       has_table_privilege(r, t, 'UPDATE') AS "update",
       has_table_privilege(r, t, 'DELETE') AS "delete"
FROM (VALUES ('analyste_1'), ('support_1'), ('bank_app'), ('auditeur_1')) AS roles(r)
CROSS JOIN (VALUES ('core.customers'), ('core.accounts'), ('core.transfers'),
                   ('core.transactions'), ('core.fraud_alerts'), ('audit.audit_log')) AS tbls(t)
ORDER BY r, t;

SELECT has_column_privilege('analyste_1', 'core.customers', 'email', 'SELECT')      AS analyste_voit_email,
       has_column_privilege('analyste_1', 'core.customers', 'birth_date', 'SELECT') AS analyste_voit_naissance;
