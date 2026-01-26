defmodule InventoryLocatorWeb.AssistHelpers do
  @moduledoc """
  Shared helper functions for Assist functionality.
  """

  @valid_fields [:manufacturer, :model, :description]

  @spec safe_to_field_atom(String.t()) :: {:ok, atom()} | {:error, :invalid_field}
  def safe_to_field_atom(str) do
    atom = String.to_existing_atom(str)

    if atom in @valid_fields do
      {:ok, atom}
    else
      {:error, :invalid_field}
    end
  rescue
    ArgumentError -> {:error, :invalid_field}
  end

  @spec valid_fields() :: [atom()]
  def valid_fields, do: @valid_fields
end
