defmodule Livebook.Nk.Util do
  alias Livebook.Hubs.Provider

  def show_fs() do
    IO.puts("FILE SYSTEMS: #{inspect(Livebook.Hubs.get_file_systems())}")

    hub = Livebook.Hubs.fetch_hub!(Livebook.Hubs.Personal.id())
    IO.puts("HUB FS: #{inspect(Provider.get_file_systems(hub))}")
  end

  def create_s3() do
    url = System.get_env("NK_S3_BUCKET")

    fs = %Livebook.FileSystem.S3{
      id: "nk-s3",
      bucket_url: url,
      external_id: nil,
      region: Livebook.FileSystem.S3.region_from_url(url),
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      hub_id: Livebook.Hubs.Personal.id()
    }

    hub = Livebook.Hubs.fetch_hub!(Livebook.Hubs.Personal.id())
    :ok = Livebook.Hubs.Provider.create_file_system(hub, fs)
  end
end
