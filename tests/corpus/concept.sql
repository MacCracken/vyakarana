-- vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
-- Re-sync when vidya adds a SQL reference sample.
--
-- Demonstrates dialect-neutral SQL: DDL, DML, joins, CTEs,
-- window functions, conditional expressions, and the case-
-- insensitive keyword behaviour (mixed UPPER / lower / Mixed).

/*
 * Schema setup. Block comments work. Line comments use `--`.
 * String literals use single quotes; double-quoted identifiers
 * are the standard form (MySQL extends this with backtick
 * quoting; this stand-in stays standard).
 */

-- ── DDL ─────────────────────────────────────────────────────────────

CREATE TABLE users (
    id           INTEGER       PRIMARY KEY,
    email        VARCHAR(255)  NOT NULL UNIQUE,
    display_name VARCHAR(80),
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active    BOOLEAN       NOT NULL DEFAULT TRUE
);

CREATE TABLE posts (
    id           INTEGER       PRIMARY KEY,
    author_id    INTEGER       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title        TEXT          NOT NULL,
    body         TEXT,
    published_at TIMESTAMP,
    score        NUMERIC(10,2) DEFAULT 0
);

CREATE INDEX posts_author_idx ON posts(author_id);

-- ── DML — case-mixing on purpose to exercise ADR 0011 ──────────────

select id, email
from   users
where  is_active = true
  and  created_at >= '2026-01-01';

Select COUNT(*) AS user_count From users;

INSERT INTO posts (id, author_id, title, body, published_at)
VALUES (1, 42, 'first post', 'body text', CURRENT_TIMESTAMP);

UPDATE users
SET    display_name = 'Renamed User'
WHERE  id = 42;

-- ── Join with subquery + aggregation ───────────────────────────────

SELECT  u.id,
        u.email,
        COUNT(p.id)         AS post_count,
        MAX(p.published_at) AS last_post_at
FROM    users u
LEFT JOIN posts p ON p.author_id = u.id
WHERE   u.is_active = TRUE
GROUP BY u.id, u.email
HAVING  COUNT(p.id) > 0
ORDER BY last_post_at DESC NULLS LAST
LIMIT   100;

-- ── CTE + window function ──────────────────────────────────────────

WITH ranked_posts AS (
    SELECT id,
           author_id,
           title,
           score,
           ROW_NUMBER() OVER (
               PARTITION BY author_id
               ORDER BY     score DESC
           ) AS rank_within_author
    FROM   posts
    WHERE  published_at IS NOT NULL
)
SELECT *
FROM   ranked_posts
WHERE  rank_within_author <= 3;

-- ── CASE expression + COALESCE ─────────────────────────────────────

SELECT id,
       CASE
           WHEN score >= 100 THEN 'hot'
           WHEN score >= 10  THEN 'warm'
           ELSE                   'cold'
       END                                   AS heat,
       COALESCE(display_name, email, 'anon') AS display
FROM   users u
JOIN   posts p ON p.author_id = u.id;

-- ── Cleanup ────────────────────────────────────────────────────────

DROP INDEX IF EXISTS posts_author_idx;
DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS users;

-- 2.3.2 error-hole coverage: dialect punctuation. MySQL quotes
-- identifiers with backticks and comments with `#`; PostgreSQL
-- uses `$1` positional parameters and `~` for regex match.
SELECT `token`, `kind`
  FROM `scan_log`                        # MySQL line comment
 WHERE kind ~ '^ident'
   AND source_id = $1;
