defmodule InventoryLocator.Accounts do
  @moduledoc false
  import Ecto.Query

  alias InventoryLocator.Accounts.InviteCode
  alias InventoryLocator.Accounts.User
  alias InventoryLocator.Accounts.UserIdentity
  alias InventoryLocator.Repo

  require Logger

  # Users

  @spec get_user(integer()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user!(integer()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  @spec find_or_create_local_user(String.t()) :: User.t()
  def find_or_create_local_user(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        user

      nil ->
        {:ok, user} =
          %User{}
          |> User.changeset(%{name: "Local Admin", email: email, role: "admin"})
          |> Repo.insert()

        user
    end
  end

  @spec update_user_from_oauth(User.t(), Ueberauth.Auth.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_from_oauth(user, auth) do
    attrs =
      %{}
      |> maybe_put(:name, auth.info.name)
      |> maybe_put(:avatar_url, auth.info.image)

    user |> User.changeset(attrs) |> Repo.update()
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec get_user_by_provider(String.t(), String.t()) :: User.t() | nil
  def get_user_by_provider(provider, provider_uid) do
    Repo.one(
      from(u in User,
        join: i in UserIdentity,
        on: i.user_id == u.id,
        where: i.provider == ^provider and i.provider_uid == ^provider_uid
      )
    )
  end

  @spec add_identity(User.t(), String.t(), String.t()) :: {:ok, UserIdentity.t()} | {:error, Ecto.Changeset.t()}
  def add_identity(user, provider, provider_uid) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{provider: provider, provider_uid: provider_uid, user_id: user.id})
    |> Repo.insert()
  end

  @spec register_user_from_oauth(map(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_invite | Ecto.Changeset.t()}
  def register_user_from_oauth(oauth_info, invite_code_str) do
    Repo.transaction(fn ->
      case validate_and_claim_invite(invite_code_str) do
        {:ok, invite} ->
          user_attrs = %{
            name: oauth_info.name,
            email: oauth_info.email,
            avatar_url: oauth_info.avatar_url,
            role: invite.role
          }

          case create_user_with_identity(user_attrs, oauth_info.provider, oauth_info.provider_uid) do
            {:ok, user} ->
              _invite = mark_invite_used(invite, user.id)
              user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @spec create_user_with_identity(map(), String.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp create_user_with_identity(user_attrs, provider, provider_uid) do
    with {:ok, user} <- %User{} |> User.changeset(user_attrs) |> Repo.insert(),
         identity_attrs = %{provider: provider, provider_uid: provider_uid, user_id: user.id},
         {:ok, _identity} <- %UserIdentity{} |> UserIdentity.changeset(identity_attrs) |> Repo.insert() do
      {:ok, user}
    end
  end

  # Invite Codes

  @spec create_invite_code(integer() | nil, String.t()) :: {:ok, InviteCode.t()} | {:error, Ecto.Changeset.t()}
  def create_invite_code(created_by_id, role) do
    attrs = %{
      code: InviteCode.generate_code(),
      role: role,
      expires_at: InviteCode.default_expiry(),
      created_by_id: created_by_id
    }

    %InviteCode{}
    |> InviteCode.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_invite_codes(boolean()) :: [InviteCode.t()]
  def list_invite_codes(include_expired) do
    query =
      from(ic in InviteCode,
        left_join: creator in assoc(ic, :created_by),
        left_join: used_by in assoc(ic, :used_by),
        order_by: [desc: ic.inserted_at, desc: ic.id],
        preload: [created_by: creator, used_by: used_by]
      )

    query =
      if include_expired do
        query
      else
        now = DateTime.utc_now()
        from(ic in query, where: ic.expires_at > ^now or not is_nil(ic.used_at))
      end

    Repo.all(query)
  end

  @spec revoke_invite_code(integer()) :: {:ok, InviteCode.t()} | {:error, :not_found | :already_used}
  def revoke_invite_code(id) do
    case Repo.get(InviteCode, id) do
      nil ->
        {:error, :not_found}

      %InviteCode{used_at: used_at} when not is_nil(used_at) ->
        {:error, :already_used}

      invite ->
        invite
        |> InviteCode.changeset(%{
          expires_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> Repo.update()
    end
  end

  @spec validate_and_claim_invite(String.t()) :: {:ok, InviteCode.t()} | {:error, :invalid_invite}
  defp validate_and_claim_invite(code_str) do
    invite = Repo.one(from(ic in InviteCode, where: ic.code == ^code_str))

    if invite && InviteCode.valid?(invite) do
      {:ok, invite}
    else
      {:error, :invalid_invite}
    end
  end

  @spec mark_invite_used(InviteCode.t(), integer()) :: InviteCode.t()
  defp mark_invite_used(invite, user_id) do
    invite
    |> InviteCode.changeset(%{used_at: DateTime.truncate(DateTime.utc_now(), :second), used_by_id: user_id})
    |> Repo.update!()
  end
end
