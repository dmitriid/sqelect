defmodule ConnectionTest do
  use ExUnit.Case, async: true

  alias Sqelect.DbConnection.Query
  alias Sqelect.DbConnection.Result

  setup do
    opts = [database: ":memory:", backoff_type: :stop, show_sensitive_data_on_connection_error: true]
    {:ok, pid} = DBConnection.start_link(Sqelect.DbConnection.Protocol, opts)

    query = %Query{name: "", statement: "CREATE TABLE uniques (a int UNIQUE)"}
    {:ok, _, _} = DBConnection.prepare_execute(pid, query, [])

    {:ok, [pid: pid]}
  end

  test "prepare twice", %{pid: pid} do
    query = %Query{name: "42", statement: "SELECT 42"}
    assert {:ok, query} = DBConnection.prepare(pid, query)
    assert {:error, %ArgumentError{}} = DBConnection.prepare(pid, query)
  end

  test "prepare failure case", %{pid: pid} do
    query = %Query{name: "test", statement: "huh"}
    assert {:error, err} = DBConnection.prepare(pid, query)
    assert %Sqelect.DbConnection.Error{message: "near \"huh\": syntax error",
                                      sqlite: %{code: :sqlite_error}} = err
  end

  test "prepare, execute and close", %{pid: pid} do
    query = %Query{name: "42", statement: "SELECT 42"}
    assert {:ok, query} = DBConnection.prepare(pid, query)

    assert {:ok, _, %Result{rows: [[42]]}} = DBConnection.execute(pid, query, [])
    assert {:ok, _, %Result{rows: [[42]]}} = DBConnection.execute(pid, query, [])
    assert {:ok, %Result{}} = DBConnection.close(pid, query)
    assert {:ok, _, %Result{rows: [[42]]}} = DBConnection.execute(pid, query, [])
  end

  test "wrong number of placeholders", context do
    pid = context[:pid]

    query = %Query{name: "value", statement: "SELECT ?1"}
    assert {:ok, query} = DBConnection.prepare(pid, query)
    assert {:error, %ArgumentError{message: "parameters must match number of placeholders in query"}} =
      DBConnection.execute(pid, query, [])
  end
end
