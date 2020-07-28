defmodule Sqelect do
  @moduledoc false
  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL,
      driver: :sqlitex

  import String, only: [to_integer: 1]

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  # ====================================================================================================================
  # Callbacks
  # ====================================================================================================================

  @impl true
  def storage_down(opts) do
    database = Keyword.get(opts, :database)
    case File.rm(database) do
      {:error, :enoent} ->
        {:error, :already_down}
      result ->
        File.rm(database <> "-shm") # ignore results for these files
        File.rm(database <> "-wal")
        result
    end
  end

  # TODO: proper storage status
  @impl true
  def storage_status(_opts) do
    :up
  end

  @impl true
  def storage_up(opts) do
    storage_up_with_path(Keyword.get(opts, :database), opts)
  end

  def supports_ddl_transaction?, do: true

  # ====================================================================================================================
  # Private functions
  # ====================================================================================================================

  defp storage_up_with_path(nil, opts) do
    raise ArgumentError,
          """
          No SQLite database path specified. Please check the configuration for your Repo.
          Your config/*.exs file should have something like this in it:

            config :my_app, MyApp.Repo,
              adapter: Sqlite.Ecto2,
              database: "/path/to/sqlite/database"

          Options provided were:

          #{inspect opts, pretty: true}

          """
  end

  defp storage_up_with_path(database, _opts) do
    if File.exists?(database) do
      {:error, :already_up}
    else
      database |> Path.dirname |> File.mkdir_p!
      {:ok, db} = Sqlitex.open(database)
      :ok = Sqlitex.exec(db, "PRAGMA journal_mode = WAL")
      {:ok, [[journal_mode: "wal"]]} = Sqlitex.query(db, "PRAGMA journal_mode")
      Sqlitex.close(db)
      :ok
    end
  end

  # ====================================================================================================================
  # Custom SQLite Types
  # ====================================================================================================================

  @impl true
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(:utc_datetime, type), do: [&date_decode/1, type]
  def loaders(:naive_datetime, type), do: [&date_decode/1, type]
  def loaders({:embed, _} = type, _),
      do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders({:map, _}, type), do: [&json_decode/1, type]
  def loaders({:array, _}, type), do: [&json_decode/1, type]
  def loaders(:float, type), do: [&float_decode/1, type]
  def loaders(_primitive, type) do
    [type]
  end

  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x), do: {:ok, x}

  defp date_decode(<<year :: binary-size(4), "-",
    month :: binary-size(2), "-",
    day :: binary-size(2)>>)
    do
    {:ok, {to_integer(year), to_integer(month), to_integer(day)}}
  end
  defp date_decode(<<year :: binary-size(4), "-",
    month :: binary-size(2), "-",
    day :: binary-size(2), " ",
    hour :: binary-size(2), ":",
    minute :: binary-size(2), ":",
    second :: binary-size(2), ".",
    microsecond :: binary-size(6)>>)
    do
    {:ok, {{to_integer(year), to_integer(month), to_integer(day)},
      {to_integer(hour), to_integer(minute), to_integer(second), to_integer(microsecond)}}}
  end
  defp date_decode(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x),
       do: {:ok, Application.get_env(:ecto, :json_library).decode!(x)}
  defp json_decode(x),
       do: {:ok, x}

  defp float_decode(x) when is_integer(x), do: {:ok, x / 1}
  defp float_decode(x), do: {:ok, x}

  @impl true
  def dumpers(:binary, type), do: [type, &blob_encode/1]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(:boolean, type), do: [type, &bool_encode/1]
  def dumpers({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers(:time, type), do: [type, &time_encode/1]
  def dumpers(:naive_datetime, type), do: [type, &naive_datetime_encode/1]
  def dumpers(_primitive, type), do: [type]

  defp blob_encode(value), do: {:ok, {:blob, value}}

  defp bool_encode(false), do: {:ok, 0}
  defp bool_encode(true), do: {:ok, 1}

  defp time_encode(value) do
    {:ok, value}
  end

  defp naive_datetime_encode(value) do
    {:ok, NaiveDateTime.to_iso8601(value)}
  end
end
