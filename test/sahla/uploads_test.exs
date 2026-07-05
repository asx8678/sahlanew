defmodule Sahla.UploadsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Sahla.Uploads

  @pdf <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25>>

  setup do
    dir = Path.join(System.tmp_dir!(), "sahla_uploads_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  defp upload_fixture(path, filename) do
    %Plug.Upload{path: path, filename: filename}
  end

  test "stores file with generated UUID filename outside original name", %{dir: dir} do
    path = Path.join(System.tmp_dir!(), "orig.jpg")
    File.write!(path, valid_jpg())

    assert {:ok, meta} = Uploads.store(upload_fixture(path, "../etc/passwd"), uploads_dir: dir)
    assert String.ends_with?(meta.path, ".jpg")
    assert String.length(Path.basename(meta.path, ".jpg")) == 36
    refute meta.path =~ "passwd"
    assert meta.content_type == "image/jpeg"
    assert meta.size > 0
  end

  test "rejects unknown magic bytes", %{dir: dir} do
    path = Path.join(System.tmp_dir!(), "unknown.bin")
    File.write!(path, <<0x00, 0x00, 0x00, 0x00>>)

    assert {:error, :unknown_type} =
             Uploads.store(upload_fixture(path, "unknown.bin"), uploads_dir: dir)
  end

  test "rejects disallowed content type", %{dir: dir} do
    path = Path.join(System.tmp_dir!(), "script.gif")
    File.write!(path, <<0x47, 0x49, 0x46, 0x38>>)

    assert {:error, :disallowed_type} =
             Uploads.store(upload_fixture(path, "script.gif"),
               uploads_dir: dir,
               allowed_types: ["image/jpeg"]
             )
  end

  test "caps pdf size at default 8MB", %{dir: dir} do
    path = Path.join(System.tmp_dir!(), "big.pdf")
    # 8 MB + 1 byte
    big = @pdf <> :crypto.strong_rand_bytes(8 * 1024 * 1024 + 1 - byte_size(@pdf))
    File.write!(path, big)

    assert {:error, :too_large} = Uploads.store(upload_fixture(path, "big.pdf"), uploads_dir: dir)
  end

  test "path traversal cannot escape uploads dir", %{dir: dir} do
    assert {:error, :forbidden} = Uploads.read("../etc/passwd", uploads_dir: dir)
  end

  test "read returns stored bytes for safe basename", %{dir: dir} do
    path = Path.join(System.tmp_dir!(), "read.jpg")
    File.write!(path, valid_jpg())
    {:ok, meta} = Uploads.store(upload_fixture(path, "read.jpg"), uploads_dir: dir)

    basename = Path.basename(meta.path)
    assert {:ok, bytes, _path, "image/jpeg"} = Uploads.read(basename, uploads_dir: dir)
    assert is_binary(bytes)
  end

  defp valid_jpg do
    # A minimal valid 1x1 JPEG created via Image so libvips re-encoding succeeds.
    Image.new!(1, 1)
    |> Image.write!(:memory, suffix: ".jpg")
  end
end
