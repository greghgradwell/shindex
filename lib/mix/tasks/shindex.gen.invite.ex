defmodule Mix.Tasks.Shindex.Gen.Invite do
  @shortdoc "Generates an invite code for new user registration"

  use Mix.Task

  alias InventoryLocator.Accounts.InviteCode
  alias InventoryLocator.Repo

  @impl true
  @spec run([String.t()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    role = parse_role(args)

    attrs = %{
      code: InviteCode.generate_code(),
      role: role,
      expires_at: InviteCode.default_expiry()
    }

    case %InviteCode{} |> InviteCode.changeset(attrs) |> Repo.insert() do
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
      {[role: role], _, _} when role in ~w(admin member) -> role
      {[role: other], _, _} -> Mix.raise("Invalid role: #{other}. Must be 'admin' or 'member'.")
      _ -> Mix.raise("Missing required --role flag. Usage: mix shindex.gen.invite --role admin|member")
    end
  end
end
