defmodule Sahla.CSVTest do
  use ExUnit.Case, async: true

  alias Sahla.CSV

  test "maps each row to header-keyed values and trims whitespace" do
    csv = "a, b ,c\n1,2,3\n"

    assert CSV.parse(csv) == [%{"a" => "1", "b" => "2", "c" => "3"}]
  end

  test "honours quoted fields with embedded commas and escaped quotes" do
    csv = ~s(name,note\n"Wafa, SA","he said ""hi""")

    assert CSV.parse(csv) == [%{"name" => "Wafa, SA", "note" => ~s(he said "hi")}]
  end

  test "skips blank lines and handles CRLF endings" do
    csv = "a,b\r\n1,2\r\n\r\n3,4\r\n"

    assert CSV.parse(csv) == [%{"a" => "1", "b" => "2"}, %{"a" => "3", "b" => "4"}]
  end

  test "an empty input yields an empty list" do
    assert CSV.parse("") == []
    assert CSV.parse("\n  \n") == []
  end
end
