-- 0001: the Notes table.
-- Migrations run in file-name order, once each, recorded in dbo.SchemaVersions.
-- Rules: never edit a migration that has been released; add a new file instead.
-- Keep changes backward-compatible (add, don't rename or drop in the same release),
-- so the previous app version still works if we roll back.

CREATE TABLE dbo.Notes
(
    Id        INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Notes PRIMARY KEY,
    Title     NVARCHAR(100)      NOT NULL,
    Body      NVARCHAR(1000)     NULL,
    CreatedAt DATETIME2(0)       NOT NULL
);
