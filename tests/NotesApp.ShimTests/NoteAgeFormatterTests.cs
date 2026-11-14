using System;
using Microsoft.QualityTools.Testing.Fakes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using NotesApp.Core;

namespace NotesApp.ShimTests
{
    /// <summary>
    /// NoteAgeFormatter reads DateTime.Now itself, so the only way to pin "now" in a
    /// test is a shim. (The better long-term fix is to inject the clock, like NoteService.)
    /// </summary>
    [TestClass]
    public class NoteAgeFormatterTests
    {
        private static readonly DateTime FixedNow = new DateTime(2026, 11, 14, 12, 0, 0);

        private static string DescribeAt(DateTime createdAt)
        {
            using (ShimsContext.Create())
            {
                System.Fakes.ShimDateTime.NowGet = () => FixedNow;
                return NoteAgeFormatter.Describe(createdAt);
            }
        }

        [TestMethod]
        public void Less_than_a_minute_is_just_now()
        {
            Assert.AreEqual("just now", DescribeAt(FixedNow.AddSeconds(-30)));
        }

        [TestMethod]
        public void Minutes_are_counted()
        {
            Assert.AreEqual("5 minutes ago", DescribeAt(FixedNow.AddMinutes(-5)));
        }

        [TestMethod]
        public void One_hour_is_singular()
        {
            Assert.AreEqual("1 hour ago", DescribeAt(FixedNow.AddHours(-1)));
        }

        [TestMethod]
        public void Days_are_counted()
        {
            Assert.AreEqual("3 days ago", DescribeAt(FixedNow.AddDays(-3)));
        }
    }
}
