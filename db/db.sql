DROP SCHEMA IF EXISTS dbproject CASCADE;
CREATE SCHEMA dbproject;
CREATE EXTENSION IF NOT EXISTS citext;

DROP TABLE IF EXISTS dbproject."User" CASCADE;
DROP TABLE IF EXISTS dbproject."Post" CASCADE;
DROP TABLE IF EXISTS dbproject."Thread" CASCADE;
DROP TABLE IF EXISTS dbproject."Forum" CASCADE;
DROP TABLE IF EXISTS dbproject."Vote" CASCADE;
DROP TABLE IF EXISTS dbproject."Users_by_Forum" CASCADE;

CREATE UNLOGGED TABLE dbproject."User"
(
    Id SERIAL PRIMARY KEY,
    NickName CITEXT UNIQUE NOT NULL,
    FullName TEXT NOT NULL,
    About TEXT,
    Email CITEXT UNIQUE NOT NULL
);

CREATE UNLOGGED TABLE dbproject."Forum"
(
    Id SERIAL PRIMARY KEY,
    Title TEXT NOT NULL,
    "user" CITEXT REFERENCES dbproject."User"(NickName) NOT NULL,
    Slug CITEXT UNIQUE NOT NULL,
    Posts INT,
    Threads INT
);

CREATE UNLOGGED TABLE dbproject."Thread"
(
    Id SERIAL PRIMARY KEY,
    Title TEXT NOT NULL,
    Author CITEXT REFERENCES dbproject."User"(NickName) NOT NULL,
    Forum CITEXT REFERENCES dbproject."Forum"(Slug) NOT NULL,
    Message TEXT NOT NULL,
    Votes INT,
    Slug CITEXT UNIQUE DEFAULT citext(1),
    Created TIMESTAMP WITH TIME ZONE
);


CREATE UNLOGGED TABLE dbproject."Post"
(
    Id SERIAL PRIMARY KEY,
    Parent INT DEFAULT 0,
    Author CITEXT REFERENCES dbproject."User"(NickName) NOT NULL,
    Message TEXT NOT NULL,
    IsEdited bool NOT NULL DEFAULT FALSE,
    Forum CITEXT REFERENCES dbproject."Forum"(Slug) NOT NULL,
    Thread INT REFERENCES dbproject."Thread"(Id) NOT NULL,
    Created TIMESTAMP WITH TIME ZONE DEFAULT now(),
    Path INT[] DEFAULT ARRAY []::INTEGER[]
);

CREATE UNLOGGED TABLE dbproject."Users_by_Forum"
(
    Id SERIAL PRIMARY KEY,
    Forum CITEXT NOT NULL,
    "user" CITEXT REFERENCES dbproject."User"(NickName) NOT NULL,
    CONSTRAINT onlyOneUser UNIQUE (Forum, "user")
);

CREATE UNLOGGED TABLE dbproject."Vote"
(
    Id SERIAL PRIMARY KEY,
    ThreadId INT REFERENCES dbproject."Thread"(id) NOT NULL,
    "user" CITEXT REFERENCES dbproject."User"(NickName) NOT NULL,
    Value INT NOT NULL,
    CONSTRAINT onlyOneVote UNIQUE (ThreadId, "user")
);

-- adding a new voice
CREATE OR REPLACE FUNCTION add_new_voice() RETURNS TRIGGER AS $$
BEGIN
    UPDATE dbproject."Thread" t SET votes = t.votes + NEW.Value WHERE t.Id = NEW.threadid;
    RETURN NULL;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER voice_trigger
    AFTER INSERT ON dbproject."Vote"
    FOR EACH ROW EXECUTE PROCEDURE add_new_voice();

-- changing voice
CREATE OR REPLACE FUNCTION change_voice() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.value <> NEW.value
    THEN UPDATE dbproject."Thread" t SET votes = (t.votes + NEW.value * 2) WHERE t.Id = NEW.threadid;
    END IF;
    RETURN NEW;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER voice_update_trigger
    AFTER UPDATE ON dbproject."Vote"
    FOR EACH ROW EXECUTE PROCEDURE change_voice();

-- add new thread
CREATE OR REPLACE FUNCTION inc_forum_threads() RETURNS TRIGGER AS $$
BEGIN
    UPDATE dbproject."Forum" SET threads = threads + 1 WHERE NEW.Forum = slug;
    INSERT INTO dbproject."Users_by_Forum" (forum, "user") VALUES (NEW.Forum, NEW.Author)
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER create_thread_trigger
    AFTER INSERT ON dbproject."Thread"
    FOR EACH ROW EXECUTE PROCEDURE inc_forum_threads();

-- adding a post
CREATE OR REPLACE FUNCTION add_post() RETURNS TRIGGER AS $$
BEGIN
--  increase counter
    UPDATE dbproject."Forum" SET posts = posts + 1 WHERE Slug = NEW.forum;
--  add user to table forum-user
    INSERT INTO dbproject."Users_by_Forum" (forum, "user") VALUES (NEW.forum, NEW.author)
    ON CONFLICT DO NOTHING;
--  write path
    NEW.path = (SELECT P.path FROM dbproject."Post" P WHERE P.id = NEW.parent LIMIT 1) || NEW.id;
    RETURN NEW;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER add_post
    BEFORE INSERT ON dbproject."Post"
    FOR EACH ROW EXECUTE PROCEDURE add_post();

CREATE INDEX IF NOT EXISTS post_path ON dbproject."Post" (path);
CREATE INDEX IF NOT EXISTS post_path_1 ON dbproject."Post" ((path[1]));
CREATE INDEX IF NOT EXISTS post_id_path1 ON dbproject."Post" (id, (path[1]));
CREATE INDEX IF NOT EXISTS post_forum ON dbproject."Post" (forum);
CREATE INDEX IF NOT EXISTS post_thread ON dbproject."Post" (thread);

CREATE INDEX IF NOT EXISTS user_nick ON dbproject."User" USING hash (nickname);
CREATE INDEX IF NOT EXISTS user_email ON dbproject."User" USING hash(email);
CREATE INDEX IF NOT EXISTS forum_users_user ON dbproject."Users_by_Forum" USING hash ("user");

CREATE INDEX IF NOT EXISTS forum_slug ON dbproject."Forum" USING hash(slug);
CREATE INDEX IF NOT EXISTS thread_slug ON dbproject."Thread" USING hash(slug);
CREATE INDEX IF NOT EXISTS thread_forum ON dbproject."Thread" (forum);
CREATE INDEX IF NOT EXISTS thread_created ON dbproject."Thread" (created);
CREATE INDEX IF NOT EXISTS thread_created_forum ON dbproject."Thread" (forum, created);

CREATE UNIQUE INDEX IF NOT EXISTS votes_nickname_thread_nickname ON dbproject."Vote" (ThreadId, "user");
