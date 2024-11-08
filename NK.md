##

* Forked https://github.com/livebook-dev/livebook into https://github.com/kalta/livebook
* git clone https://github.com/kalta/livebook nk_livebook
* git remote add upstream https://github.com/livebook-dev/livebook.git

Now we have two remotes, origin and upstream. Copy the tags from upstream:
* git fetch upstream --tags    
* checkout of upstream v0.14, created branch v0.14-nk, pushed to upstream 

* mix deps.get
* MIX_ENV=prod ELIXIR_ERL_OPTIONS="-epmd_module Elixir.Livebook.EPMD" mix phx.server


export BASE_IMAGE=hexpm/elixir:1.16.3-erlang-26.2.5.5-debian-buster-20240612-slim
export VARIANT=default
docker build --build-arg BASE_IMAGE=$BASE_IMAGE --build-arg VARIANT=$VARIANT . -t livebook

# standalone, embedded
docker run -p 8080:8080 -p 8081:8081 -e LIVEBOOK_DEFAULT_RUNTIME=standalone livebook:latest


LIVEBOOK_DEFAULT_RUNTIME=attached:rcp-infra-0@172.29.6.162:horasAtodasPIZZA




