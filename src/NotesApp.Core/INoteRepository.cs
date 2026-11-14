using System.Collections.Generic;

namespace NotesApp.Core
{
    /// <summary>Storage for notes. The seam that lets NoteService be unit-tested with Moq.</summary>
    public interface INoteRepository
    {
        IList<Note> GetAll();
        int Add(Note note);
        void Delete(int id);
    }
}
