defmodule InventoryLocatorWeb.AuthController do
  use InventoryLocatorWeb, :controller

  alias InventoryLocator.Accounts
  alias InventoryLocator.Accounts.User

  require Logger

  plug Ueberauth

  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    provider_uid = to_string(auth.uid)

    case Accounts.get_user_by_provider(provider, provider_uid) do
      nil ->
        handle_unknown_identity(conn, auth, provider, provider_uid)

      user ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Welcome back, #{user.name}!")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.warning("OAuth failure: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/landing")
  end

  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def register(conn, _params) do
    case get_session(conn, :pending_oauth) do
      nil ->
        conn
        |> put_flash(:error, "No pending registration. Please sign in first.")
        |> redirect(to: ~p"/landing")

      _oauth_info ->
        render(conn, :register, error: nil)
    end
  end

  @spec create_registration(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_registration(conn, %{"invite_code" => invite_code}) do
    case get_session(conn, :pending_oauth) do
      nil ->
        conn
        |> put_flash(:error, "No pending registration. Please sign in first.")
        |> redirect(to: ~p"/landing")

      oauth_info ->
        oauth_info = atomize_oauth_info(oauth_info)

        case Accounts.register_user_from_oauth(oauth_info, String.trim(invite_code)) do
          {:ok, user} ->
            conn
            |> configure_session(renew: true)
            |> delete_session(:pending_oauth)
            |> put_session(:user_id, user.id)
            |> put_flash(:info, "Welcome, #{user.name}! Your account has been created.")
            |> redirect(to: ~p"/")

          {:error, :invalid_invite} ->
            render(conn, :register, error: "Invalid or expired invite code.")

          {:error, changeset} ->
            Logger.warning("Registration failed: #{inspect(changeset)}")
            render(conn, :register, error: "Registration failed. Please try again.")
        end
    end
  end

  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been signed out.")
    |> redirect(to: ~p"/landing")
  end

  @spec handle_unknown_identity(Plug.Conn.t(), Ueberauth.Auth.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp handle_unknown_identity(conn, auth, provider, provider_uid) do
    session_user_id = get_session(conn, :user_id)

    cond do
      is_integer(session_user_id) ->
        link_identity_to_user(conn, Accounts.get_user(session_user_id), provider, provider_uid)

      (user = email_verified_user(auth)) ->
        link_identity_to_user(conn, user, provider, provider_uid)

      true ->
        oauth_info = %{
          name: extract_name(auth),
          email: extract_email(auth),
          avatar_url: extract_avatar(auth),
          provider: provider,
          provider_uid: provider_uid
        }

        conn
        |> put_session(:pending_oauth, oauth_info)
        |> redirect(to: ~p"/auth/register")
    end
  end

  @spec link_identity_to_user(Plug.Conn.t(), User.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp link_identity_to_user(conn, user, provider, provider_uid) do
    case Accounts.add_identity(user, provider, provider_uid) do
      {:ok, _identity} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "#{String.capitalize(provider)} account linked. Welcome back, #{user.name}!")
        |> redirect(to: ~p"/")

      {:error, changeset} ->
        Logger.warning("Failed to link identity: #{inspect(changeset)}")

        conn
        |> put_flash(:error, "Failed to link #{provider} account. Please try again.")
        |> redirect(to: ~p"/landing")
    end
  end

  # Only auto-link when the OAuth provider verifies email ownership.
  # GitHub and LinkedIn both do; gate here so adding an unverified provider won't auto-link.
  @verified_email_providers ~w(github linkedin)

  @spec email_verified_user(Ueberauth.Auth.t()) :: User.t() | nil
  defp email_verified_user(%{provider: provider, info: %{email: email}})
       when provider in @verified_email_providers and is_binary(email) and email != "" do
    Accounts.get_user_by_email(email)
  end

  defp email_verified_user(_auth), do: nil

  @spec extract_name(Ueberauth.Auth.t()) :: String.t()
  defp extract_name(%{info: %{name: name}}) when is_binary(name) and name != "", do: name
  defp extract_name(%{info: %{nickname: nick}}) when is_binary(nick) and nick != "", do: nick
  defp extract_name(_auth), do: "User"

  @spec extract_email(Ueberauth.Auth.t()) :: String.t() | nil
  defp extract_email(%{info: %{email: email}}) when is_binary(email) and email != "", do: email
  defp extract_email(_auth), do: nil

  @spec extract_avatar(Ueberauth.Auth.t()) :: String.t() | nil
  defp extract_avatar(%{info: %{image: url}}) when is_binary(url) and url != "", do: url
  defp extract_avatar(_auth), do: nil

  @spec atomize_oauth_info(map()) :: map()
  defp atomize_oauth_info(info) when is_map(info) do
    Map.new(info, fn
      {k, v} when is_binary(k) ->
        {String.to_existing_atom(k), v}

      {k, v} when is_atom(k) ->
        {k, v}

      {k, v} ->
        Logger.warning("Unexpected key type in OAuth info: #{inspect(k)}")
        {k, v}
    end)
  end
end
