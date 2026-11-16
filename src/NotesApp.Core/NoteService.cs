using System;
using System.Collections.Generic;
using System.Linq;

namespace NotesApp.Core
{
    /// <summary>
    /// The business rules for notes. Testable: storage and the clock are injected.
    /// </summary>
    public class NoteService
    {
        public const int MaxTitleLength = 100;
        public const int MaxBodyLength = 1000;

        private readonly INoteRepository _repository;
        private readonly Func<DateTime> _now;

        public NoteService(INoteRepository repository, Func<DateTime> now)
        {
            _repository = repository ?? throw new ArgumentNullException(nameof(repository));
            _now = now ?? throw new ArgumentNullException(nameof(now));
        }

        /// <summary>All notes, newest first.</summary>
        public IList<Note> GetNotes()
        {
            return _repository.GetAll().OrderByDescending(n => n.CreatedAt).ToList();
        }

        /// <summary>Adds a note. Returns null on success, or the validation message.</summary>
        public string AddNote(string title, string body)
        {
            var cleanTitle = (title ?? string.Empty).Trim();
            var cleanBody = (body ?? string.Empty).Trim();

            if (cleanTitle.Length == 0)
                return "A title is required.Please enter a title.";
            if (cleanTitle.Length > MaxTitleLength)
                return "The title can be at most " + MaxTitleLength + " characters.";
            if (cleanBody.Length > MaxBodyLength)
                return "The note can be at most " + MaxBodyLength + " characters.";

            _repository.Add(new Note { Title = cleanTitle, Body = cleanBody, CreatedAt = _now() });
            return null;
        }

        public void DeleteNote(int id)
        {
            if (id <= 0)
                throw new ArgumentOutOfRangeException(nameof(id), "Note id must be positive.");

            _repository.Delete(id);
        }

        public int CountNotes()
        {
            return _repository.GetAll().Count();
        }
    }
}
