-- Runs automatically on the FIRST postgres start.
-- Re-running compose later won't re-execute this; safe.

-- n8n
CREATE USER n8n WITH PASSWORD :'n8n_password';
CREATE DATABASE n8n OWNER n8n;

-- plausible
CREATE USER plausible WITH PASSWORD :'plausible_password';
CREATE DATABASE plausible OWNER plausible;
