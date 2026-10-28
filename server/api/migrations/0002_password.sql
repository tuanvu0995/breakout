-- Optional sign-up (email + password) so a player can get the same account back after reinstalling.
ALTER TABLE accounts ADD COLUMN email TEXT COLLATE NOCASE;
ALTER TABLE accounts ADD COLUMN pw_hash TEXT;
CREATE UNIQUE INDEX accounts_email ON accounts(email);
-- Cloud copy of campaign progress (JSON) for registered players.
ALTER TABLE accounts ADD COLUMN progress TEXT;
