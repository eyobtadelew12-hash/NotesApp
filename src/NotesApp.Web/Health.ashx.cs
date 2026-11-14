using System;
using System.Configuration;
using System.Data.SqlClient;
using System.Web;

namespace NotesApp.Web
{
    /// <summary>
    /// GET /health.ashx — checked by the release right after IIS is switched to a new
    /// release. 200 only if the app starts AND can read its Notes table with the app pool
    /// identity (Integrated Security). Anything else makes the deploy roll back.
    /// The X-Release-Version header proves the NEW version is the one answering.
    /// </summary>
    public class Health : IHttpHandler
    {
        public bool IsReusable => true;

        public void ProcessRequest(HttpContext context)
        {
            var response = context.Response;
            response.ContentType = "text/plain";
            response.Cache.SetCacheability(HttpCacheability.NoCache);

            var environment = ConfigurationManager.AppSettings["Environment"] ?? "unknown";
            var version = ConfigurationManager.AppSettings["ReleaseVersion"] ?? "unknown";
            response.AppendHeader("X-Release-Version", version);

            try
            {
                var builder = new SqlConnectionStringBuilder(
                    ConfigurationManager.ConnectionStrings["NotesDb"].ConnectionString) { ConnectTimeout = 5 };

                using (var connection = new SqlConnection(builder.ConnectionString))
                using (var command = new SqlCommand("SELECT COUNT(*) FROM dbo.Notes", connection) { CommandTimeout = 5 })
                {
                    connection.Open();
                    command.ExecuteScalar();
                }

                response.StatusCode = 200;
                response.Write("Healthy " + environment + " " + version);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("Health check failed: " + ex);
                response.StatusCode = 503;
                response.TrySkipIisCustomErrors = true;
                response.Write("Unhealthy " + environment + " " + version);
            }
        }
    }
}
