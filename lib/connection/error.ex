defmodule Sqelect.Connection.Error do
  @moduledoc false
  defexception [:message, :sqlite, :connection_id]
end
