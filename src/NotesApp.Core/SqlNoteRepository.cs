using System;
using System.Collections.Generic;
using System.Data.SqlClient;

namespace NotesApp.Core
{
    /// <summary>SQL Server storage (Integrated Security: the IIS app pool identity signs in).</summary>
    public class SqlNoteRepository : INoteRepository
    {
        private readonly string _connectionString;

        public SqlNoteRepository(string connectionString)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
                throw new ArgumentException("A connection string is required.", nameof(connectionString));
            _connectionString = connectionString;
        }

        public IList<Note> GetAll()
        {
            var notes = new List<Note>();
            using (var conn = new SqlConnection(_connectionString))
            using (var cmd = new SqlCommand("SELECT Id, Title, Body, CreatedAt FROM dbo.Notes", conn))
            {
                conn.Open();
                using (var reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        notes.Add(new Note
                        {
                            Id = reader.GetInt32(0),
                            Title = reader.GetString(1),
                            Body = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                            CreatedAt = reader.GetDateTime(3)
                        });
                    }
                }
            }
            return notes;
        }

        public int Add(Note note)
        {
            using (var conn = new SqlConnection(_connectionString))
            using (var cmd = new SqlCommand(
                "INSERT INTO dbo.Notes (Title, Body, CreatedAt) OUTPUT INSERTED.Id VALUES (@title, @body, @createdAt)", conn))
            {
                cmd.Parameters.AddWithValue("@title", note.Title);
                cmd.Parameters.AddWithValue("@body", (object)note.Body ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@createdAt", note.CreatedAt);
                conn.Open();
                return (int)cmd.ExecuteScalar();
            }
        }

        public void Delete(int id)
        {
            using (var conn = new SqlConnection(_connectionString))
            using (var cmd = new SqlCommand("DELETE FROM dbo.Notes WHERE Id = @id", conn))
            {
                cmd.Parameters.AddWithValue("@id", id);
                conn.Open();
                cmd.ExecuteNonQuery();
            }
        }
    }
}
