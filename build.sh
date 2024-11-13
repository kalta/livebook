# only for testing, use nkd build helm -r rcp_lb_main

export BASE_IMAGE=hexpm/elixir:1.16.3-erlang-26.2.5.5-debian-buster-20240612-slim
export VARIANT=default
rsync -av --delete ../rcp2_svc/apps/norma nk_deps/

docker build --build-arg BASE_IMAGE=$BASE_IMAGE --build-arg VARIANT=$VARIANT . -t livebook
