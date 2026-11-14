using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using NotesApp.Core;

namespace NotesApp.Tests
{
    [TestClass]
    public class NoteServiceTests
    {
        private static readonly DateTime Now = new DateTime(2026, 11, 14, 10, 0, 0);

        private Mock<INoteRepository> _repository;
        private NoteService _service;

        [TestInitialize]
        public void SetUp()
        {
            _repository = new Mock<INoteRepository>();
            _service = new NoteService(_repository.Object, () => Now);
        }

        [TestMethod]
        public void AddNote_saves_a_trimmed_note_with_the_current_time()
        {
            var error = _service.AddNote("  Buy milk  ", "  2 litres ");

            Assert.IsNull(error);
            _repository.Verify(r => r.Add(It.Is<Note>(n =>
                n.Title == "Buy milk" && n.Body == "2 litres" && n.CreatedAt == Now)), Times.Once);
        }

        [TestMethod]
        [DataRow(null)]
        [DataRow("")]
        [DataRow("   ")]
        public void AddNote_rejects_an_empty_title(string title)
        {
            var error = _service.AddNote(title, "body");

            Assert.AreEqual("A title is required.", error);
            _repository.Verify(r => r.Add(It.IsAny<Note>()), Times.Never);
        }

        [TestMethod]
        public void AddNote_rejects_a_title_that_is_too_long()
        {
            var error = _service.AddNote(new string('x', NoteService.MaxTitleLength + 1), "body");

            StringAssert.Contains(error, "at most " + NoteService.MaxTitleLength);
            _repository.Verify(r => r.Add(It.IsAny<Note>()), Times.Never);
        }

        [TestMethod]
        public void AddNote_rejects_a_body_that_is_too_long()
        {
            var error = _service.AddNote("Title", new string('x', NoteService.MaxBodyLength + 1));

            StringAssert.Contains(error, "at most " + NoteService.MaxBodyLength);
        }

        [TestMethod]
        public void GetNotes_returns_newest_first()
        {
            _repository.Setup(r => r.GetAll()).Returns(new List<Note>
            {
                new Note { Id = 1, Title = "old", CreatedAt = Now.AddDays(-2) },
                new Note { Id = 2, Title = "new", CreatedAt = Now },
                new Note { Id = 3, Title = "mid", CreatedAt = Now.AddDays(-1) }
            });

            var notes = _service.GetNotes();

            CollectionAssert.AreEqual(new[] { 2, 3, 1 }, new[] { notes[0].Id, notes[1].Id, notes[2].Id });
        }

        [TestMethod]
        public void DeleteNote_deletes_through_the_repository()
        {
            _service.DeleteNote(7);

            _repository.Verify(r => r.Delete(7), Times.Once);
        }

        [TestMethod]
        public void DeleteNote_rejects_an_invalid_id()
        {
            Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => _service.DeleteNote(0));
        }
    }
}
