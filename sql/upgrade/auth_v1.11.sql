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
