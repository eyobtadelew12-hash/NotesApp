<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Default.aspx.cs" Inherits="NotesApp.Web.Default" %>
<!DOCTYPE html>
<html lang="en">
<head runat="server">
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Notes</title>
    <link href="Content/site.css" rel="stylesheet" />
</head>
<body>
    <form id="form1" runat="server">
        <header class="top">
            <h1>Notes</h1>
            <span class="env">
                <asp:Literal ID="litEnvironment" runat="server" />
                &middot; v<asp:Literal ID="litVersion" runat="server" />
            </span>
        </header>

        <main class="page">
            <section class="card">
                <h2>New note</h2>
                <label for="txtTitle">Title</label>
                <asp:TextBox ID="txtTitle" runat="server" MaxLength="100" ClientIDMode="Static" />
                <label for="txtBody">Note</label>
                <asp:TextBox ID="txtBody" runat="server" TextMode="MultiLine" Rows="3" ClientIDMode="Static" />
                <asp:Label ID="lblError" runat="server" CssClass="error" Visible="false" />
                <asp:Button ID="btnAdd" runat="server" Text="Add note" OnClick="btnAdd_Click" CssClass="primary" />
            </section>

            <asp:Repeater ID="rptNotes" runat="server" OnItemCommand="rptNotes_ItemCommand">
                <ItemTemplate>
                    <article class="card note">
                        <div class="note-head">
                            <h3><%#: Eval("Title") %></h3>
                            <span class="age"><%#: AgeOf(Eval("CreatedAt")) %></span>
                        </div>
                        <p><%#: Eval("Body") %></p>
                        <asp:LinkButton runat="server" CommandName="Delete" CommandArgument='<%# Eval("Id") %>'
                            CssClass="delete" OnClientClick="return confirm('Delete this note?');">Delete</asp:LinkButton>
                    </article>
                </ItemTemplate>
            </asp:Repeater>

            <asp:Panel ID="pnlEmpty" runat="server" CssClass="empty" Visible="false">No notes yet. Add your first one above.</asp:Panel>
        </main>
    </form>
</body>
</html>
