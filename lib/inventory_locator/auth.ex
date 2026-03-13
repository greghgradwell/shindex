defmodule InventoryLocator.Auth do
  @moduledoc false

  alias InventoryLocator.Accounts
  alias InventoryLocator.Accounts.User

  @local_email "local@shindex.local"

  @spec auth_required?() :: boolean()
  def auth_required? do
    Application.get_env(:inventory_locator, :auth_required)
  end

  @spec resolve_user(map()) :: {:ok, User.t()} | :unauthenticated | :stale_session
  def resolve_user(session) do
    if auth_required?() do
      case session["user_id"] do
        nil ->
          :unauthenticated

        user_id ->
          case Accounts.get_user(user_id) do
            %User{} = user -> {:ok, user}
            nil -> :stale_session
          end
      end
    else
      {:ok, local_user()}
    end
  end

  @spec ensure_local_user() :: :ok
  def ensure_local_user do
    _ = if !auth_required?(), do: local_user()

    :ok
  end

  @spec local_user() :: User.t()
  defp local_user do
    Accounts.find_or_create_local_user(@local_email)
  end
end
