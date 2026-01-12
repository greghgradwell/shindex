defmodule InventoryLocator.Media do
  @moduledoc false

  @max_width 1920
  @max_height 1080
  @jpeg_quality 85
  @uploads_dir "priv/static/uploads"
  @fetch_timeout 5_000
  @max_download_size 10_000_000

  # Private/internal IP patterns that should never be fetched (SSRF protection)
  # Note: URI.parse returns IPv6 hosts WITHOUT brackets (e.g., "::1" not "[::1]")
  @forbidden_host_patterns [
    ~r/^localhost$/i,
    ~r/^127\./,
    ~r/^10\./,
    ~r/^172\.(1[6-9]|2[0-9]|3[01])\./,
    ~r/^192\.168\./,
    ~r/^169\.254\./,
    ~r/^0\./,
    ~r/^::1?$/,
    ~r/^metadata\.google\.internal$/i,
    ~r/^metadata\.internal$/i
  ]

  @spec fetch_image_from_url(String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch_image_from_url(url) do
    with :ok <- validate_url(url),
         :ok <- validate_host_allowed(url),
         {:ok, content_type} <- check_content_type_via_head(url) do
      do_fetch_image(url, content_type)
    end
  end

  @spec process_and_save_photo(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def process_and_save_photo(binary_data, original_filename) do
    with {:ok, image} <- Image.from_binary(binary_data),
         {:ok, resized} <- resize_to_bounds(image),
         filename = generate_filename(original_filename),
         path = Path.join([@uploads_dir, filename]),
         :ok <- ensure_uploads_dir(),
         {:ok, _} <- Image.write(resized, path, quality: @jpeg_quality) do
      {:ok, filename}
    end
  end

  @spec resize_to_bounds(Vix.Vips.Image.t()) :: {:ok, Vix.Vips.Image.t()} | {:error, term()}
  defp resize_to_bounds(image) do
    width = Image.width(image)
    height = Image.height(image)

    cond do
      width <= @max_width and height <= @max_height ->
        {:ok, image}

      width / height > @max_width / @max_height ->
        Image.thumbnail(image, @max_width)

      true ->
        Image.resize(image, @max_height / height)
    end
  end

  @spec generate_filename(String.t()) :: String.t()
  defp generate_filename(_original_filename) do
    timestamp = DateTime.to_unix(DateTime.utc_now(), :millisecond)
    random = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "#{timestamp}_#{random}.jpg"
  end

  @spec ensure_uploads_dir() :: :ok
  defp ensure_uploads_dir do
    File.mkdir_p!(@uploads_dir)
    :ok
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

  @spec check_content_type_via_head(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp check_content_type_via_head(url) do
    case Req.head(url, receive_timeout: @fetch_timeout, max_redirects: 3) do
      {:ok, %{status: 200, headers: headers}} ->
        content_type = get_content_type(headers)

        if valid_image_type?(content_type) do
          {:ok, content_type}
        else
          {:error, :not_an_image}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  @spec do_fetch_image(String.t(), String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  defp do_fetch_image(url, content_type) do
    req_opts = [
      receive_timeout: @fetch_timeout,
      max_redirects: 3,
      decode_body: false
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body}} when byte_size(body) <= @max_download_size ->
        filename = extract_filename_from_url(url, content_type)
        {:ok, body, filename}

      {:ok, %{status: 200, body: body}} when byte_size(body) > @max_download_size ->
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
      [value | _] -> value
      _ -> nil
    end
  end

  @spec valid_image_type?(String.t() | nil) :: boolean()
  defp valid_image_type?(nil), do: false
  defp valid_image_type?(content_type), do: String.starts_with?(content_type, "image/")

  @spec extract_filename_from_url(String.t(), String.t() | nil) :: String.t()
  defp extract_filename_from_url(url, content_type) do
    uri = URI.parse(url)
    path_filename = uri.path && Path.basename(uri.path)

    if path_filename && String.contains?(path_filename, ".") do
      path_filename
    else
      ext = content_type_to_ext(content_type)
      "url_image#{ext}"
    end
  end

  @spec content_type_to_ext(String.t() | nil) :: String.t()
  defp content_type_to_ext("image/jpeg"), do: ".jpg"
  defp content_type_to_ext("image/jpg"), do: ".jpg"
  defp content_type_to_ext("image/png"), do: ".png"
  defp content_type_to_ext("image/webp"), do: ".webp"
  defp content_type_to_ext("image/gif"), do: ".gif"
  defp content_type_to_ext(_), do: ".jpg"
end
