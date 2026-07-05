defmodule SahlaWeb.UploadController do
  @moduledoc """
  Serves private uploads from `:uploads_dir` (§12).

  Access is restricted to:
    * an authenticated admin with the `:leads` capability, or
    * the owning quote via a valid quote `token` parameter.

  The basename in the URL is a generated UUID filename; path traversal is rejected.
  """
  use SahlaWeb, :controller

  def show(conn, %{"basename" => basename}) do
    with {:ok, bytes, _path, sniffed_type} <- Sahla.Uploads.read(basename),
         :ok <- authorize(conn, basename) do
      content_type = sniffed_type

      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("content-disposition", "inline")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, bytes)
    else
      {:error, :forbidden} -> send_resp(conn, 403, "Forbidden")
      {:error, :enoent} -> send_resp(conn, 404, "Not found")
      {:error, _} -> send_resp(conn, 404, "Not found")
    end
  end

  defp authorize(conn, basename) do
    cond do
      conn.assigns[:current_admin] ->
        :ok

      token = conn.params["token"] ->
        authorize_by_token(basename, token)

      true ->
        {:error, :forbidden}
    end
  end

  # The quote token path is used for funnel relevé documents: the token itself
  # is the capability for that quote's uploads.
  defp authorize_by_token(basename, token) do
    case Sahla.Quoting.get_quote_by_token(token) do
      nil ->
        {:error, :forbidden}

      quote_record ->
        if quote_record.releve_doc_path == basename do
          :ok
        else
          {:error, :forbidden}
        end
    end
  end
end
