defmodule InventoryLocator.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias InventoryLocator.Accounts.User

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import InventoryLocator.DataCase

      alias InventoryLocator.Repo
    end
  end

  setup tags do
    InventoryLocator.DataCase.setup_sandbox(tags)
    :ok
  end

  @spec setup_sandbox(map()) :: pid()
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(InventoryLocator.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @spec errors_on(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @spec create_test_user(map()) :: User.t()
  def create_test_user(attrs) do
    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(%{name: "Test User #{System.unique_integer([:positive])}", role: "admin"}, attrs))
      |> InventoryLocator.Repo.insert()

    user
  end

  @spec create_test_inventory(map()) :: InventoryLocator.Inventory.Inv.t()
  def create_test_inventory(attrs) do
    attrs =
      if Map.has_key?(attrs, :user_id) do
        attrs
      else
        user = create_test_user(%{name: "Inventory Owner #{System.unique_integer([:positive])}", role: "admin"})
        Map.put(attrs, :user_id, user.id)
      end

    {:ok, inv} =
      InventoryLocator.Inventory.create_inventory(
        Map.merge(%{name: "Test Inventory #{System.unique_integer([:positive])}"}, attrs)
      )

    inv
  end
end
