defmodule InventoryLocator.AccountsTest do
  use InventoryLocator.DataCase, async: true

  alias InventoryLocator.Accounts
  alias InventoryLocator.Accounts.InviteCode
  alias InventoryLocator.Accounts.User

  describe "get_user_by_email/1" do
    test "returns user when email matches" do
      user = insert_user(%{name: "Test User", email: "test@example.com"})

      found = Accounts.get_user_by_email("test@example.com")
      assert found.id == user.id
    end

    test "returns nil when no user has that email" do
      assert Accounts.get_user_by_email("nobody@example.com") == nil
    end
  end

  describe "get_user_by_provider/2" do
    test "returns user when identity exists" do
      user = insert_user(%{name: "Test User"})
      insert_identity(user, "github", "12345")

      found = Accounts.get_user_by_provider("github", "12345")
      assert found.id == user.id
    end

    test "returns nil when identity does not exist" do
      assert Accounts.get_user_by_provider("github", "nonexistent") == nil
    end
  end

  describe "add_identity/3" do
    test "links a new provider to an existing user" do
      user = insert_user(%{name: "Test User"})

      assert {:ok, identity} = Accounts.add_identity(user, "github", "gh-123")
      assert identity.provider == "github"
      assert identity.provider_uid == "gh-123"
      assert identity.user_id == user.id
    end

    test "returns error for duplicate provider+uid" do
      user = insert_user(%{name: "Test User"})
      insert_identity(user, "github", "gh-123")

      assert {:error, changeset} = Accounts.add_identity(user, "github", "gh-123")
      assert errors_on(changeset)[:provider]
    end
  end

  describe "register_user_from_oauth/2" do
    test "first user becomes admin" do
      invite = insert_invite(%{})

      oauth_info = %{
        name: "First User",
        email: "first@example.com",
        avatar_url: "https://example.com/avatar.png",
        provider: "github",
        provider_uid: "111"
      }

      assert {:ok, user} = Accounts.register_user_from_oauth(oauth_info, invite.code)
      assert user.role == "admin"
      assert user.name == "First User"
    end

    test "subsequent users become members" do
      _admin = insert_user(%{name: "Admin", role: "admin"})
      invite = insert_invite(%{})

      oauth_info = %{
        name: "Second User",
        email: "second@example.com",
        avatar_url: nil,
        provider: "github",
        provider_uid: "222"
      }

      assert {:ok, user} = Accounts.register_user_from_oauth(oauth_info, invite.code)
      assert user.role == "member"
    end

    test "fails with invalid invite code" do
      oauth_info = %{
        name: "User",
        email: "user@example.com",
        avatar_url: nil,
        provider: "github",
        provider_uid: "333"
      }

      assert {:error, :invalid_invite} = Accounts.register_user_from_oauth(oauth_info, "BADCODE1")
    end

    test "fails with expired invite code" do
      invite = insert_invite(%{expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)})

      oauth_info = %{
        name: "User",
        email: "user@example.com",
        avatar_url: nil,
        provider: "github",
        provider_uid: "444"
      }

      assert {:error, :invalid_invite} = Accounts.register_user_from_oauth(oauth_info, invite.code)
    end

    test "fails with already-used invite code" do
      user = insert_user(%{name: "Existing"})
      invite = insert_invite(%{used_at: DateTime.utc_now(), used_by_id: user.id})

      oauth_info = %{
        name: "User",
        email: "user@example.com",
        avatar_url: nil,
        provider: "github",
        provider_uid: "555"
      }

      assert {:error, :invalid_invite} = Accounts.register_user_from_oauth(oauth_info, invite.code)
    end

    test "marks invite code as used" do
      invite = insert_invite(%{})

      oauth_info = %{
        name: "User",
        email: "user@example.com",
        avatar_url: nil,
        provider: "github",
        provider_uid: "666"
      }

      assert {:ok, _user} = Accounts.register_user_from_oauth(oauth_info, invite.code)

      updated_invite = Repo.get!(InviteCode, invite.id)
      assert updated_invite.used_at
      assert updated_invite.used_by_id
    end
  end

  describe "create_invite_code/1" do
    test "creates a valid invite code" do
      user = insert_user(%{name: "Admin", role: "admin"})

      assert {:ok, invite} = Accounts.create_invite_code(user.id)
      assert String.length(invite.code) == 8
      assert invite.created_by_id == user.id
      assert invite.used_at == nil
      assert DateTime.after?(invite.expires_at, DateTime.utc_now())
    end
  end

  describe "list_invite_codes/0" do
    test "returns all invite codes ordered by most recent" do
      user = insert_user(%{name: "Admin", role: "admin"})
      {:ok, _first} = Accounts.create_invite_code(user.id)
      {:ok, second} = Accounts.create_invite_code(user.id)

      codes = Accounts.list_invite_codes()
      assert length(codes) == 2
      assert hd(codes).id == second.id
    end
  end

  describe "revoke_invite_code/1" do
    test "expires an unused invite code" do
      user = insert_user(%{name: "Admin", role: "admin"})
      {:ok, invite} = Accounts.create_invite_code(user.id)

      assert {:ok, revoked} = Accounts.revoke_invite_code(invite.id)
      assert DateTime.before?(revoked.expires_at, DateTime.utc_now())
    end

    test "returns error for already-used codes" do
      invite = insert_invite(%{used_at: DateTime.utc_now()})

      assert {:error, :already_used} = Accounts.revoke_invite_code(invite.id)
    end

    test "returns error for nonexistent codes" do
      assert {:error, :not_found} = Accounts.revoke_invite_code(-1)
    end
  end

  describe "InviteCode.generate_code/0" do
    test "generates 8-character uppercase codes" do
      code = InviteCode.generate_code()
      assert String.length(code) == 8
      assert code == String.upcase(code)
    end

    test "generates unique codes" do
      codes = for _ <- 1..100, do: InviteCode.generate_code()
      assert length(Enum.uniq(codes)) == 100
    end
  end

  describe "User.admin?/1" do
    test "returns true for admin" do
      assert User.admin?(%User{role: "admin"})
    end

    test "returns false for member" do
      refute User.admin?(%User{role: "member"})
    end
  end

  # Test helpers

  @spec insert_user(map()) :: User.t()
  defp insert_user(attrs) do
    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(%{name: "Test", role: "member"}, attrs))
      |> Repo.insert()

    user
  end

  @spec insert_identity(User.t(), String.t(), String.t()) :: InventoryLocator.Accounts.UserIdentity.t()
  defp insert_identity(user, provider, uid) do
    alias InventoryLocator.Accounts.UserIdentity

    {:ok, identity} =
      %UserIdentity{}
      |> UserIdentity.changeset(%{provider: provider, provider_uid: uid, user_id: user.id})
      |> Repo.insert()

    identity
  end

  @spec insert_invite(map()) :: InviteCode.t()
  defp insert_invite(overrides) do
    attrs =
      Map.merge(
        %{code: InviteCode.generate_code(), expires_at: InviteCode.default_expiry()},
        overrides
      )

    {:ok, invite} =
      %InviteCode{}
      |> InviteCode.changeset(attrs)
      |> Repo.insert()

    invite
  end
end
