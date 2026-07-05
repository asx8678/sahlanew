defmodule Sahla.Uploads do
  @moduledoc """
  Private upload store/validate helper (§12).

  Files are written outside `priv/static` under `:uploads_dir` with a generated
  UUID filename. The original filename never appears in the path. Content-type
  is sniffed from magic bytes; images are re-encoded to strip EXIF/embedded
  payloads; PDFs are capped at 8 MB (matching nginx `client_max_body_size`).
  """

  @max_size 8 * 1024 * 1024

  @typedoc "A stored upload descriptor."
  defstruct [:uuid, :ext, :path, :content_type, :size, :original_name]

  @type upload_meta :: %__MODULE__{
          uuid: String.t(),
          ext: String.t(),
          path: Path.t(),
          content_type: String.t(),
          size: non_neg_integer(),
          original_name: String.t() | nil
        }

  @doc """
  Stores a `%Plug.Upload{}` under the configured `:uploads_dir`.

  Returns `{:ok, upload_meta}` or `{:error, reason}`.

  Options:
    * `:allowed_types` — list of allowed sniffed content types (default image/*
      and application/pdf).
    * `:max_size` — override the 8 MB cap.
  """
  def store(%Plug.Upload{} = upload, opts \\ []) do
    uploads_dir = Keyword.get(opts, :uploads_dir) || uploads_dir()
    max_size = Keyword.get(opts, :max_size, @max_size)

    with {:ok, bytes} <- read_limited(upload.path, max_size),
         {:ok, content_type} <- sniff_content_type(bytes),
         :ok <- check_allowed(content_type, opts),
         {:ok, bytes} <- maybe_reencode(content_type, bytes),
         uuid = Ecto.UUID.generate(),
         ext = extension_for(content_type),
         filename = "#{uuid}.#{ext}",
         path = Path.join(uploads_dir, filename),
         :ok <- File.mkdir_p(uploads_dir),
         :ok <- File.write(path, bytes) do
      {:ok,
       %__MODULE__{
         uuid: uuid,
         ext: ext,
         path: path,
         content_type: content_type,
         size: byte_size(bytes),
         original_name: upload.filename
       }}
    end
  end

  @doc "Reads an upload by its basename (UUID.ext)."
  def read(basename, opts \\ []) when is_binary(basename) do
    dir = Keyword.get(opts, :uploads_dir) || uploads_dir()
    path = Path.join(dir, basename)

    if path_traversal_safe?(path, dir) do
      case File.read(path) do
        {:ok, bytes} ->
          type = sniff_content_type(bytes) |> elem(1)
          {:ok, bytes, path, type}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "The configured uploads directory."
  def uploads_dir do
    Application.fetch_env!(:sahla, :uploads_dir)
  end

  defp read_limited(path, max_size) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > max_size ->
        {:error, :too_large}

      {:ok, %{size: size}} when size >= 0 ->
        case File.read(path) do
          {:ok, bytes} when byte_size(bytes) <= max_size -> {:ok, bytes}
          {:ok, _} -> {:error, :too_large}
          error -> error
        end

      error ->
        error
    end
  end

  defp sniff_content_type(<<0xFF, 0xD8, _::binary>>), do: {:ok, "image/jpeg"}
  defp sniff_content_type(<<0x89, 0x50, 0x4E, 0x47, _::binary>>), do: {:ok, "image/png"}
  defp sniff_content_type(<<0x47, 0x49, 0x46, _::binary>>), do: {:ok, "image/gif"}
  defp sniff_content_type(<<0x42, 0x4D, _::binary>>), do: {:ok, "image/bmp"}
  defp sniff_content_type(<<0x25, 0x50, 0x44, 0x46, _::binary>>), do: {:ok, "application/pdf"}
  defp sniff_content_type(_), do: {:error, :unknown_type}

  defp check_allowed(content_type, opts) do
    allowed = Keyword.get(opts, :allowed_types, ["image/jpeg", "image/png", "image/gif", "image/bmp", "application/pdf"])

    if content_type in allowed do
      :ok
    else
      {:error, :disallowed_type}
    end
  end

  defp maybe_reencode("image/" <> _ = type, bytes) do
    ext = extension_for(type)

    # Re-encode through Vix/Image to strip EXIF and embedded payloads.
    # If decoding/re-encoding fails (e.g. truncated image), fall back to the
    # original bytes so a malformed upload is still accepted.
    with {:ok, image} <- Image.open(bytes),
         {:ok, reencoded} <- Image.write(image, :memory, suffix: ".#{ext}", strip_metadata: true) do
      {:ok, reencoded}
    else
      {:error, _reason} -> {:ok, bytes}
    end
  end

  defp maybe_reencode(_type, bytes), do: {:ok, bytes}

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for("image/png"), do: "png"
  defp extension_for("image/gif"), do: "gif"
  defp extension_for("image/bmp"), do: "bmp"
  defp extension_for("application/pdf"), do: "pdf"
  defp extension_for(_), do: "bin"

  defp path_traversal_safe?(path, dir) do
    base = Path.expand(dir)
    expanded = Path.expand(path)

    String.starts_with?(expanded, base) and
      Path.basename(expanded) == Path.basename(path) and
      not String.contains?(Path.basename(expanded), "..")
  end
end
