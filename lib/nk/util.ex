defmodule Livebook.Nk.Util do
  alias Livebook.Hubs.Provider

  def show_fs() do
    IO.puts("FILE SYSTEMS: #{inspect(Livebook.Hubs.get_file_systems())}")

    hub = Livebook.Hubs.fetch_hub!(Livebook.Hubs.Personal.id())
    IO.puts("HUB FS: #{inspect(Provider.get_file_systems(hub))}")
  end

  def create_s3() do
    id = System.get_env("AWS_ACCESS_KEY_ID")
    secret = System.get_env("AWS_SECRET_ACCESS_KEY")
    bucket = System.get_env("NK_S3_BUCKET")
    hub = Livebook.Hubs.fetch_hub!(Livebook.Hubs.Personal.id())

    fs = %Livebook.FileSystem.S3{
      id: "nk-s3",
      bucket_url: bucket,
      access_key_id: id,
      secret_access_key: secret
      # hub_id: hub
    }

    :ok = Provider.create_file_system(hub, fs)
  end
end
