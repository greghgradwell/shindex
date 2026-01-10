defmodule InventoryLocator.Media do
  @moduledoc false

  @max_width 1920
  @max_height 1080
  @jpeg_quality 85
  @uploads_dir "priv/static/uploads"

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
end
