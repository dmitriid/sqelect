# What

This is a shameless copy-pasta of [sqlite_ecto2](https://github.com/elixir-sqlite/sqlite_ecto2)
in a feeble attempt to make it compatible with Ecto3.

Unfortunately, this is *not a direct fork*. To understand the changes to Ecto 3 I went ahead and copy-pasta-ed
each module callback by callback and function by function until it compiled and started running tests. So if you
run a diff, it will show that everything has changed. This is not entirely true :)

# Status

Tests fail with 

```
{"busy",0}
{"busy",1}
{"busy",2}
{"busy",3}
{"busy",4}
{"busy",5}

+   def handle_deallocate(_query, _cursor, _opts, state) do
+     {:error, %Sqelect.DbConnection.Error{message: "Cursors not supported"}, state}
+   end
+ 
+   def handle_declare(_query, _cursor, _opts, state) do
+     {:error, %Sqelect.DbConnection.Error{message: "Cursors not supported"}, state}
+   end

+   def handle_status(_opts, %__MODULE__{in_transaction?: in_transaction} = state) do
+     # TODO: handle transaction errors
+     case in_transaction do
+       true -> {:transaction, state}
+       _ -> {:idle, state}
+     end
+   end

+ def ping(state), do: {:ok, state}
```

## New return types

```diff
protocol.ex
defp handle_execute(%Query{statement: sql} = query, params, _sync, opts, state) do
...
      {:ok, result} ->
-        {:ok, result, state}
+        {:ok, query, result, state}
...
```

## Handle new ecto types

### INCOMPLETE: NaiveDateTime

```diff
sqelect.ex

+ def dumpers(:naive_datetime, type), do: [type, &naive_datetime_encode/1]

+ defp naive_datetime_encode(value) do
+   {:ok, NaiveDateTime.to_iso8601(value)}
+ end
```