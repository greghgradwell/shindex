defmodule InventoryLocator.Media do
  @moduledoc false

  import Ecto.Query

  alias InventoryLocator.Inventory.Document
  alias InventoryLocator.Repo

  @max_photo_width 1920
  @max_photo_height 1080
  @jpeg_quality 85

  @uploads_dir "priv/static/uploads"
  @documents_dir "priv/static/documents"

  @fetch_timeout 10_000
  @max_photo_size 10_000_000
  @max_document_size 50 * 1024 * 1024

  @photo_content_types ["image/*"]
  @document_content_types ["application/pdf", "image/png", "image/jpeg", "image/jpg"]

  @document_ext_to_mime %{
    ".pdf" => "application/pdf",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg"
  }

  @forbidden_host_patterns [
    ~r/^localhost$/i,
    ~r/^127\./,
    ~r/^10\./,
    ~r/^172\.(1[6-9]|2[0-9]|3[01])\./,
    ~r/^192\.168\./,
    ~r/^169\.254\./,
    ~r/^0\./,
    ~r/^::1?$/,
    ~r/^fc[0-9a-f]{2}:/i,
    ~r/^fe[89ab][0-9a-f]:/i,
    ~r/^metadata\.google\.internal$/i,
    ~r/^metadata\.internal$/i
  ]

  # Photo operations

  @spec fetch_image_from_url(String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch_image_from_url(url) do
    case fetch_file_from_url(url, @photo_content_types, @max_photo_size, :not_an_image) do
      {:ok, binary, filename, _content_type} -> {:ok, binary, filename}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec process_and_save_photo(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def process_and_save_photo(binary_data, original_filename) do
    with {:ok, image} <- Image.from_binary(binary_data),
         {:ok, resized} <- resize_to_bounds(image),
         filename = generate_filename(original_filename, ".jpg"),
         path = Path.join([@uploads_dir, filename]),
         :ok <- ensure_dir(@uploads_dir),
         {:ok, _} <- Image.write(resized, path, quality: @jpeg_quality) do
      {:ok, filename}
    end
  end

  # Document operations

  @spec list_documents(integer()) :: [Document.t()]
  def list_documents(item_id) do
    Document
    |> where([d], d.item_id == ^item_id)
    |> order_by([d], asc: d.inserted_at)
    |> Repo.all()
  end

  @spec get_document!(integer()) :: Document.t()
  def get_document!(id), do: Repo.get!(Document, id)

  @spec create_document(integer(), map()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def create_document(item_id, attrs) do
    %Document{}
    |> Document.changeset(Map.put(attrs, :item_id, item_id))
    |> Repo.insert()
  end

  @spec delete_document(Document.t()) :: {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def delete_document(%Document{} = document) do
    safe_path = Path.basename(document.storage_path)
    file_path = Path.join([@documents_dir, safe_path])

    case Repo.delete(document) do
      {:ok, deleted_document} ->
        case File.rm(file_path) do
          :ok ->
            :ok

          {:error, reason} ->
            require Logger

            Logger.warning("Failed to delete document file: #{file_path}, reason: #{inspect(reason)}")
        end

        {:ok, deleted_document}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec fetch_document_from_url(String.t()) ::
          {:ok, binary(), String.t(), String.t()} | {:error, term()}
  def fetch_document_from_url(url) do
    fetch_file_from_url(url, @document_content_types, @max_document_size, :not_a_document)
  end

  @spec save_document_file(binary(), String.t()) ::
          {:ok, String.t(), String.t(), integer()} | {:error, atom()}
  def save_document_file(binary, original_filename) do
    ext = original_filename |> Path.extname() |> String.downcase()

    with {:ok, content_type} <- validate_document_extension(ext),
         :ok <- validate_document_size(binary) do
      storage_path = generate_filename(original_filename, ext)
      full_path = Path.join([@documents_dir, storage_path])

      ensure_dir(@documents_dir)

      case File.write(full_path, binary) do
        :ok -> {:ok, storage_path, content_type, byte_size(binary)}
        {:error, _reason} -> {:error, :write_failed}
      end
    end
  end

  @spec max_document_size() :: integer()
  def max_document_size, do: @max_document_size

  @spec allowed_document_extensions() :: [String.t()]
  def allowed_document_extensions, do: Map.keys(@document_ext_to_mime)

  @spec allowed_document_content_types() :: [String.t()]
  def allowed_document_content_types, do: @document_content_types

  # Generic URL fetching

  @spec fetch_file_from_url(String.t(), [String.t()], pos_integer(), atom()) ::
          {:ok, binary(), String.t(), String.t()} | {:error, term()}
  defp fetch_file_from_url(url, valid_types, max_size, error_type) do
    with :ok <- validate_url(url),
         :ok <- validate_host_allowed(url),
         {:ok, content_type} <- check_content_type(url, valid_types, error_type) do
      do_fetch(url, content_type, max_size)
    end
  end

  @spec validate_url(String.t()) :: :ok | {:error, :invalid_url | :insecure_url}
  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> :ok
      %URI{scheme: "http"} -> {:error, :insecure_url}
      _ -> {:error, :invalid_url}
    end
  end

  @spec validate_host_allowed(String.t()) :: :ok | {:error, :forbidden_host}
  defp validate_host_allowed(url) do
    %URI{host: host} = URI.parse(url)

    if Enum.any?(@forbidden_host_patterns, &Regex.match?(&1, host)) do
      {:error, :forbidden_host}
    else
      :ok
    end
  end

  @spec check_content_type(String.t(), [String.t()], atom()) :: {:ok, String.t()} | {:error, term()}
  defp check_content_type(url, valid_types, error_type) do
    case Req.head(url, receive_timeout: @fetch_timeout, max_redirects: 3) do
      {:ok, %{status: 200, headers: headers}} ->
        content_type = get_content_type(headers)

        if content_type && content_type_matches?(content_type, valid_types) do
          {:ok, content_type}
        else
          {:error, error_type}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  @spec do_fetch(String.t(), String.t(), pos_integer()) ::
          {:ok, binary(), String.t(), String.t()} | {:error, term()}
  defp do_fetch(url, expected_content_type, max_size) do
    req_opts = [
      receive_timeout: @fetch_timeout,
      max_redirects: 3,
      decode_body: false
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body, headers: headers}} when byte_size(body) <= max_size ->
        actual_content_type = get_content_type(headers)

        if actual_content_type == expected_content_type do
          filename = extract_filename_from_url(url, actual_content_type)
          {:ok, body, filename, actual_content_type}
        else
          {:error, :content_type_mismatch}
        end

      {:ok, %{status: 200, body: _body}} ->
        {:error, :file_too_large}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  @spec get_content_type(%{String.t() => [String.t()]}) :: String.t() | nil
  defp get_content_type(headers) do
    case Map.get(headers, "content-type") do
      [value | _] -> value |> String.split(";") |> List.first() |> String.trim()
      _ -> nil
    end
  end

  @spec content_type_matches?(String.t(), [String.t()]) :: boolean()
  defp content_type_matches?(content_type, valid_types) do
    Enum.any?(valid_types, fn pattern ->
      if String.ends_with?(pattern, "/*") do
        prefix = String.trim_trailing(pattern, "/*")
        String.starts_with?(content_type, prefix)
      else
        content_type == pattern
      end
    end)
  end

  @spec extract_filename_from_url(String.t(), String.t()) :: String.t()
  defp extract_filename_from_url(url, content_type) do
    uri = URI.parse(url)
    path_filename = uri.path && Path.basename(uri.path)

    if path_filename && String.contains?(path_filename, ".") do
      path_filename
    else
      ext = content_type_to_ext(content_type)
      "url_file#{ext}"
    end
  end

  @spec content_type_to_ext(String.t()) :: String.t()
  defp content_type_to_ext("image/jpeg"), do: ".jpg"
  defp content_type_to_ext("image/jpg"), do: ".jpg"
  defp content_type_to_ext("image/png"), do: ".png"
  defp content_type_to_ext("image/webp"), do: ".webp"
  defp content_type_to_ext("image/gif"), do: ".gif"
  defp content_type_to_ext("application/pdf"), do: ".pdf"
  defp content_type_to_ext(_), do: ".bin"

  # Photo helpers

  @spec resize_to_bounds(Vix.Vips.Image.t()) :: {:ok, Vix.Vips.Image.t()} | {:error, term()}
  defp resize_to_bounds(image) do
    width = Image.width(image)
    height = Image.height(image)

    cond do
      width <= @max_photo_width and height <= @max_photo_height ->
        {:ok, image}

      width / height > @max_photo_width / @max_photo_height ->
        Image.thumbnail(image, @max_photo_width)

      true ->
        Image.resize(image, @max_photo_height / height)
    end
  end

  # Document helpers

  @spec validate_document_extension(String.t()) :: {:ok, String.t()} | {:error, :invalid_type}
  defp validate_document_extension(ext) do
    case Map.get(@document_ext_to_mime, ext) do
      nil -> {:error, :invalid_type}
      content_type -> {:ok, content_type}
    end
  end

  @spec validate_document_size(binary()) :: :ok | {:error, :file_too_large}
  defp validate_document_size(binary) when byte_size(binary) > @max_document_size, do: {:error, :file_too_large}

  defp validate_document_size(_binary), do: :ok

  # Shared helpers

  @spec generate_filename(String.t(), String.t()) :: String.t()
  defp generate_filename(_original_filename, ext) do
    timestamp = DateTime.to_unix(DateTime.utc_now(), :millisecond)
    random = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "#{timestamp}_#{random}#{ext}"
  end

  @spec ensure_dir(String.t()) :: :ok
  defp ensure_dir(dir) do
    File.mkdir_p!(dir)
    :ok
  end
end
