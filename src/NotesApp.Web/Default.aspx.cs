using System;
using System.Configuration;
using System.Web.UI;
using System.Web.UI.WebControls;
using NotesApp.Core;

namespace NotesApp.Web
{
    public partial class Default : Page
    {
        private NoteService _notes;

        protected void Page_Init(object sender, EventArgs e)
        {
            var connectionString = ConfigurationManager.ConnectionStrings["NotesDb"].ConnectionString;
            _notes = new NoteService(new SqlNoteRepository(connectionString), () => DateTime.Now);
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            litEnvironment.Text = Server.HtmlEncode(ConfigurationManager.AppSettings["Environment"] ?? "Unknown");
            litVersion.Text = Server.HtmlEncode(ConfigurationManager.AppSettings["ReleaseVersion"] ?? "?");

            if (!IsPostBack)
                BindNotes();
        }

        protected void btnAdd_Click(object sender, EventArgs e)
        {
            var error = _notes.AddNote(txtTitle.Text, txtBody.Text);
            if (error != null)
            {
                lblError.Text = error;
                lblError.Visible = true;
                return;
            }

            txtTitle.Text = string.Empty;
            txtBody.Text = string.Empty;
            lblError.Visible = false;
            BindNotes();
        }

        protected void rptNotes_ItemCommand(object source, RepeaterCommandEventArgs e)
        {
            if (e.CommandName == "Delete")
            {
                _notes.DeleteNote(int.Parse((string)e.CommandArgument));
                BindNotes();
            }
        }

        protected string AgeOf(object createdAt)
        {
            return NoteAgeFormatter.Describe((DateTime)createdAt);
        }

        private void BindNotes()
        {
            var notes = _notes.GetNotes();
            litCount.Text = notes.Count + " notes";
            rptNotes.DataSource = notes;
            rptNotes.DataBind();
            pnlEmpty.Visible = notes.Count == 0;
        }
    }
}
