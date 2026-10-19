-- 00_roles_db.sql : crée le propriétaire et la base (à lancer en tant que postgres)
CREATE ROLE bank_owner LOGIN;
CREATE DATABASE bankdb OWNER bank_owner;
