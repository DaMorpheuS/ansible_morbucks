app =
  case System.get_env("ECTO_APP") || System.get_env("RELEASE_NAME") do
    nil -> raise "Set ECTO_APP (or RELEASE_NAME) to your OTP app name"
    name -> String.to_atom(name)
  end

for otp_app <- [:logger, :telemetry, :ecto, :ecto_sql], do: Application.ensure_all_started(otp_app)
if Code.ensure_loaded?(Postgrex), do: Application.ensure_all_started(:postgrex)
if Code.ensure_loaded?(MyXQL), do: Application.ensure_all_started(:myxql)

repos = Application.fetch_env!(app, :ecto_repos)

Enum.each(repos, fn repo ->
  IO.puts("Starting repo #{inspect(repo)}")
  {:ok, _pid} = repo.start_link(pool_size: 2)

  repo_underscore =
    repo
    |> Module.split()
    |> List.last()
    |> Macro.underscore()

  priv_dir = app |> :code.priv_dir() |> to_string()
  migrations_path = Path.join([priv_dir, repo_underscore, "migrations"])

  IO.puts("Running migrations for #{inspect(repo)} from #{migrations_path}")
  Ecto.Migrator.run(repo, migrations_path, :up, all: true)
end)
