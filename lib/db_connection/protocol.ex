defmodule Sqelect.DbConnection.Protocol do
  @moduledoc false

  @behaviour DBConnection

  alias Sqelect.DbConnection.Query

  defstruct [:db, :db_path, :pid, :checked_out?, :in_transaction?]
  defstruct [:db, :db_path, :checked_out?, :in_transaction?]

  # ====================================================================================================================
  # Callbacks
  # ====================================================================================================================

  def checkin(%__MODULE__{checked_out?: true} = state), do: {:ok, %__MODULE__{state | checked_out?: false}}
  def checkout(%__MODULE__{checked_out?: false} = state), do: {:ok, %__MODULE__{state | checked_out?: true}}

  def connect(opts) do
    db_path = Keyword.fetch!(opts, :database)
    db_timeout = Keyword.get(opts, :db_timeout, 5000)

    {:ok, db} = Sqlitex.Server.start_link(db_path, db_timeout: db_timeout)
    :ok = Sqlitex.Server.exec(db, "PRAGMA foreign_keys = ON")
    {:ok, [[foreign_keys: 1]]} = Sqlitex.Server.query(db, "PRAGMA foreign_keys")

    {:ok, %__MODULE__{db: db, db_path: db_path, checked_out?: false, pid: db}}
    {:ok, %__MODULE__{db: db, db_path: db_path, checked_out?: false}}
  end

  def disconnect(_err, %__MODULE__{pid: pid}) do
    Supervisor.stop(pid)
  def disconnect(_exc, %__MODULE__{db: db} = _state) when db != nil do
    GenServer.stop(db)
    :ok
  end
  def disconnect(_exception, _state), do: :ok

  def handle_begin(opts, state) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "BEGIN"
      :savepoint -> "SAVEPOINT sqlite_ecto_savepoint"
    end
    new_state = %__MODULE__{state | in_transaction?: true}
    handle_transaction(sql, [timeout: Keyword.get(opts, :timeout, 5000)], new_state)
  end

  def handle_close(_query, _opts, state) do
    # no-op: esqlite doesn't expose statement close.
    # Instead it relies on statements getting garbage collected.
    res = %Sqelect.DbConnection.Result{command: :close}
    {:ok, res, state}
  end

  def handle_commit(opts, state) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "COMMIT"
      :savepoint -> "RELEASE SAVEPOINT sqlite_ecto_savepoint"
    end
    new_state = %__MODULE__{state | in_transaction?: false}
    handle_transaction(sql, [timeout: Keyword.get(opts, :timeout, 5000)], new_state)
  end

  def handle_deallocate(_query, _cursor, _opts, state) do
    {:error, %Sqelect.DbConnection.Error{message: "Cursors not supported"}, state}
  end

  def handle_declare(_query, _cursor, _opts, state) do
    {:error, %Sqelect.DbConnection.Error{message: "Cursors not supported"}, state}
  end

  def handle_execute(%Query{} = query, params, opts, state) do
    handle_execute(query, params, :sync, opts, state)
  end

  def handle_fetch(_query, _cursor, _opts, state) do
    {:error, %Sqelect.DbConnection.Error{message: "Cursors not supported"}, state}
  end

  def handle_prepare(
        %Query{statement: statement, prepared: nil} = query,
        _opts,
        %__MODULE__{checked_out?: true, db: db} = state
      )
    do
    binary_stmt = :erlang.iolist_to_binary(statement)
    case Sqlitex.Server.prepare(db, binary_stmt) do
      {:ok, prepared_info} ->
        updated_query = %{query | prepared: refined_info(prepared_info)}
        {:ok, updated_query, state}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, state)
    end
  end
  def handle_prepare(query, _opts, state) do
    query_error(state, "query #{inspect query} has already been prepared")
  end

  def handle_rollback(opts, state) do
    sql = case Keyword.get(opts, :mode, :transaction) do
      :transaction -> "ROLLBACK"
      :savepoint -> "ROLLBACK TO SAVEPOINT sqlite_ecto_savepoint"
    end
    new_state = %__MODULE__{state | in_transaction?: false}
    handle_transaction(sql, [timeout: Keyword.get(opts, :timeout, 5000)], new_state)
  end

  def handle_status(_opts, %__MODULE__{in_transaction?: in_transaction} = state) do
    # TODO: handle transaction errors
    case in_transaction do
      true -> {:transaction, state}
      _ -> {:idle, state}
    end
  end

  def ping(state), do: {:ok, state}

  # ====================================================================================================================
  # Private functions
  # ====================================================================================================================

  defp handle_transaction(stmt, opts, state) do
    {:ok, _rows} = query_rows(state.db, stmt, Keyword.merge(opts, [into: :raw_list]))
    command = command_from_sql(stmt)
    result = %Sqelect.DbConnection.Result{
      rows: nil,
      num_rows: nil,
      columns: nil,
      command: command
    }
    {:ok, result, state}
  end

  defp query_rows(db, stmt, opts) do
    Sqlitex.Server.query_rows(db, stmt, opts)
  catch
    :exit, {:timeout, _gen_server_call} ->
      {:error, %Sqelect.DbConnection.Error{message: "Timeout"}}
    :exit, ex ->
      {:error, %Sqelect.DbConnection.Error{message: inspect(ex)}}
  end

  defp command_from_sql(sql) do
    sql
    |> :erlang.iolist_to_binary
    |> String.downcase
    |> String.split(" ", parts: 3)
    |> command_from_words
  end

  defp command_from_words([verb, subject, _])
       when verb == "alter" or verb == "create" or verb == "drop"
    do
    String.to_atom("#{verb}_#{subject}")
  end

  defp command_from_words(words) when is_list(words) do
    String.to_atom(List.first(words))
  end

  defp handle_execute(%Query{statement: sql} = query, params, _sync, opts, state) do
    # Note that we rely on Sqlitex.Server to cache the prepared statement,
    # so we can simply refer to the original SQL statement here.
    case run_stmt(sql, params, opts, state) do
      {:ok, result} ->
        {:ok, query, result, state}
      other ->
        other
    end
  end

  defp run_stmt(query, params, opts, state) do
    query_opts = [
      timeout: Keyword.get(opts, :timeout, 5000),
      decode: :manual,
      types: true,
      bind: params
    ]

    command = command_from_sql(query)
    case query_rows(state.db, to_string(query), query_opts) do
      {:ok, %{rows: raw_rows, columns: raw_column_names}} ->
        {rows, num_rows, column_names} = case {raw_rows, raw_column_names} do
          {_, []} -> {nil, get_changes_count(state.db, command), nil}
          _ -> {raw_rows, length(raw_rows), raw_column_names}
        end
        {
          :ok,
          %Sqelect.DbConnection.Result{
            rows: rows,
            num_rows: num_rows,
            columns: atoms_to_strings(column_names),
            command: command
          }
        }
      {:error, :wrong_type} -> {:error, %ArgumentError{message: "Wrong type"}, state}
      {:error, {_sqlite_errcode, _message}} = err ->
        sqlite_error(err, state)
      {:error, %Sqelect.DbConnection.Error{} = err} ->
        {:error, err, state}
      {:error, :args_wrong_length} ->
        {
          :error,
          %ArgumentError{message: "parameters must match number of placeholders in query"},
          state
        }
    end
  end

  defp get_changes_count(db, command)
       when command in [:insert, :update, :delete]
    do
    {:ok, %{rows: [[changes_count]]}} = Sqlitex.Server.query_rows(db, "SELECT changes()")
    changes_count
  end
  defp get_changes_count(_db, _command), do: 1

  defp atoms_to_strings(nil), do: nil
  defp atoms_to_strings(list), do: Enum.map(list, &maybe_atom_to_string/1)

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(item), do: to_string(item)

  defp maybe_atom_to_lc_string(nil), do: nil
  defp maybe_atom_to_lc_string(item),
       do: item
           |> to_string
           |> String.downcase

  defp sqlite_error({:error, {sqlite_errcode, message}}, state) do
    {
      :error,
      %Sqelect.DbConnection.Error{
        sqlite: %{
          code: sqlite_errcode
        },
        message: to_string(message)
      },
      state
    }
  end

  defp refined_info(prepared_info) do
    types =
      prepared_info.types
      |> Enum.map(&maybe_atom_to_lc_string/1)
      |> Enum.to_list

    prepared_info
    |> Map.delete(:columns)
    |> Map.put(:column_names, atoms_to_strings(prepared_info.columns))
    |> Map.put(:types, types)
  end

  defp query_error(state, msg) do
    {:error, ArgumentError.exception(msg), state}
  end
end
