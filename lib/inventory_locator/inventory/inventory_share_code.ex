defmodule InventoryLocator.Inventory.InventoryShareCode do
  @moduledoc false
  use TypedEctoSchema

  import Ecto.Changeset

  alias InventoryLocator.Accounts.User
  alias InventoryLocator.Inventory.Inv

  @code_length 8
  @default_expiry_days 7
  @roles ~w(viewer)

  typed_schema "inventory_share_codes" do
    field :code, :string
    field :role, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :inventory, Inv
    belongs_to :used_by, User
    belongs_to :created_by, User

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(share_code, attrs) do
    share_code
    |> cast(attrs, [:code, :role, :expires_at, :used_at, :inventory_id, :used_by_id, :created_by_id])
    |> validate_required([:code, :role, :expires_at, :inventory_id, :created_by_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:code)
    |> foreign_key_constraint(:inventory_id)
    |> foreign_key_constraint(:created_by_id)
  end

  @spec generate_code() :: String.t()
  def generate_code do
    @code_length
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(padding: false)
    |> binary_part(0, @code_length)
  end

  @spec default_expiry() :: DateTime.t()
  def default_expiry do
    DateTime.utc_now()
    |> DateTime.add(@default_expiry_days, :day)
    |> DateTime.truncate(:second)
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{used_at: used_at}) when not is_nil(used_at), do: false

  def valid?(%__MODULE__{expires_at: expires_at}) do
    DateTime.after?(expires_at, DateTime.utc_now())
  end
end
