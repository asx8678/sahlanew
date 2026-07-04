defmodule Sahla.Types.IP do
  @moduledoc """
  Ecto type mapping a Postgres `inet` column to a plain IP string at runtime
  (e.g. `"196.200.1.5"`). Used for audit/rate-limit context on quotes, consents
  and audit entries. Invalid addresses fail to cast.
  """
  use Ecto.Type

  def type, do: :inet

  def cast(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, address} -> {:ok, address |> :inet.ntoa() |> List.to_string()}
      {:error, _} -> :error
    end
  end

  def cast(%Postgrex.INET{} = inet), do: {:ok, from_pg(inet)}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def load(%Postgrex.INET{} = inet), do: {:ok, from_pg(inet)}
  def load(nil), do: {:ok, nil}

  def dump(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, address} -> {:ok, %Postgrex.INET{address: address}}
      {:error, _} -> :error
    end
  end

  def dump(%Postgrex.INET{} = inet), do: {:ok, inet}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  defp from_pg(%Postgrex.INET{address: address}), do: address |> :inet.ntoa() |> List.to_string()
end
