# What

This is an attempt to update [sqlite_ecto2](https://github.com/elixir-sqlite/sqlite_ecto2) to work with Ecto 3.

Note: any code in this repo is exploratory and should be folded/merged back into sqlite_ecto2.

You can view the previous attempt in [update-attempt-the-first](https://github.com/dmitriid/sqelect/tree/update-attempt-the-first). 
This attempt exposed to some problems with how Ecto and sqlite implementations handle
connections. See the discussions in [this issue](https://github.com/elixir-sqlite/sqlite_ecto2/issues/244) 
and over at [Elixir forum](https://elixirforum.com/t/help-with-debugging-sqlites-busy-error-with-ecto3/33613).
