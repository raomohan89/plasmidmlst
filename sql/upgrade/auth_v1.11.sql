DELETE FROM sessions;
ALTER TABLE sessions ADD state text NOT NULL;
ALTER TABLE sessions ADD username text;
ALTER TABLE sessions ADD reset_password boolean;

ALTER TABLE users ADD algorithm text;
UPDATE users SET algorithm = 'md5';
ALTER TABLE users ALTER COLUMN algorithm SET NOT NULL;
ALTER TABLE users ADD cost int;
ALTER TABLE users ADD salt text;
ALTER TABLE users ADD reset_password boolean;

CREATE TABLE clients (
application text NOT NULL,
version text NOT NULL,
client_id text NOT NULL,
client_secret text NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (application, version)
);

GRANT SELECT ON clients TO apache;