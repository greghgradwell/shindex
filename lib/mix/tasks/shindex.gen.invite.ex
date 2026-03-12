defmodule Mix.Tasks.Shindex.Gen.Invite do
  @shortdoc "Generates an invite code for new user registration"

  use Mix.Task

  alias InventoryLocator.Accounts
  alias InventoryLocator.Accounts.InviteCode

  @roles InviteCode.roles()

  @impl true
  @spec run([String.t()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    role = parse_role(args)

    case Accounts.create_invite_code(nil, role) do
      {:ok, invite} ->
        Mix.shell().info("""

        Invite code created:

          Code:    #{invite.code}
          Role:    #{invite.role}
          Expires: #{Calendar.strftime(invite.expires_at, "%Y-%m-%d")}

        """)

      {:error, changeset} ->
        Mix.shell().error("Failed to create invite code: #{inspect(changeset.errors)}")
    end
  end

  @spec parse_role([String.t()]) :: String.t()
  defp parse_role(args) do
    case OptionParser.parse(args, strict: [role: :string]) do
      {[role: role], _, _} when role in @roles -> role
      {[role: other], _, _} -> Mix.raise("Invalid role: #{other}. Must be one of: #{Enum.join(@roles, ", ")}")
      _ -> Mix.raise("Missing required --role flag. Usage: mix shindex.gen.invite --role #{Enum.join(@roles, "|")}")
    end
  end
end
