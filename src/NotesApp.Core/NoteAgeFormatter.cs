using System;

namespace NotesApp.Core
{
    /// <summary>
    /// LEGACY ON PURPOSE: reads DateTime.Now directly, like a lot of old code does.
    /// It can only be unit-tested with Microsoft Fakes shims (see tests/NotesApp.ShimTests).
    /// </summary>
    public static class NoteAgeFormatter
    {
        public static string Describe(DateTime createdAt)
        {
            var age = DateTime.Now - createdAt;

            if (age < TimeSpan.FromMinutes(1)) return "just now";
            if (age < TimeSpan.FromHours(1)) return Plural((int)age.TotalMinutes, "minute") + " ago";
            if (age < TimeSpan.FromDays(1)) return Plural((int)age.TotalHours, "hour") + " ago";
            return Plural((int)age.TotalDays, "day") + " ago";
        }

        private static string Plural(int count, string unit)
        {
            return count + " " + unit + (count == 1 ? string.Empty : "s");
        }
    }
}
