defmodule SahlaWeb.UploadControllerTest do
  @moduledoc false
  use SahlaWeb.ConnCase, async: true

  alias Sahla.Accounts
  alias Sahla.Quoting
  alias Sahla.Uploads
  alias SahlaWeb.AdminAuth

  @pdf <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A>>
  @admin_password "correct horse battery staple"

  setup do
    dir =
      Path.join(System.tmp_dir!(), "sahla_uploads_ctrl_test_#{System.unique_integer([:positive])}")

    Application.put_env(:sahla, :uploads_dir, dir)
    on_exit(fn -> File.rm_rf(dir) end)
    :ok
  end

  defp store_pdf do
    path = Path.join(System.tmp_dir!(), "doc.pdf")
    File.write!(path, @pdf)
    {:ok, meta} = Uploads.store(%Plug.Upload{path: path, filename: "doc.pdf"})
    meta
  end

  defp log_in_admin(conn, admin) do
    conn
    |> Map.replace!(:secret_key_base, SahlaWeb.Endpoint.config(:secret_key_base))
    |> init_test_session(%{})
    |> AdminAuth.log_in_admin(admin)
    |> AdminAuth.fetch_current_admin([])
  end

  test "unauthenticated request without token is rejected", %{conn: conn} do
    meta = store_pdf()
    conn = get(conn, ~p"/uploads/#{Path.basename(meta.path)}")
    assert conn.status == 403
  end

  test "admin can fetch an upload", %{conn: conn} do
    meta = store_pdf()

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "ops-#{System.unique_integer([:positive])}@sahla.ma",
        password: @admin_password,
        role: :ops
      })

    conn = log_in_admin(conn, admin) |> get(~p"/uploads/#{Path.basename(meta.path)}")
    assert conn.status == 200
    assert conn.resp_body == @pdf
    assert hd(get_resp_header(conn, "content-type")) =~ "application/pdf"
  end

  test "quote token can fetch its own relevé upload", %{conn: conn} do
    meta = store_pdf()
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, quote} =
      Quoting.upsert_step(quote, :driver, %{
        "releve_doc_path" => Path.basename(meta.path),
        "birth_date" => "1990-01-01",
        "license_date" => "2010-01-01"
      })

    conn = get(conn, ~p"/uploads/#{Path.basename(meta.path)}?token=#{quote.token}")
    assert conn.status == 200
    assert conn.resp_body == @pdf
  end

  test "quote token cannot fetch another quote's upload", %{conn: conn} do
    meta = store_pdf()
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    conn = get(conn, ~p"/uploads/#{Path.basename(meta.path)}?token=#{quote.token}")
    assert conn.status == 403
  end

  test "invalid token is rejected", %{conn: conn} do
    meta = store_pdf()
    conn = get(conn, ~p"/uploads/#{Path.basename(meta.path)}?token=not-a-real-token")
    assert conn.status == 403
  end

  test "path traversal in basename is rejected", %{conn: conn} do
    conn = get(conn, "/uploads/%2Fetc%2Fpasswd?token=any-token")
    assert conn.status in [403, 404]
  end
end
