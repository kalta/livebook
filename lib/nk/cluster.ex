defmodule Nk.Cluster do
  @moduledoc """
    Tries to connect to other nodes in the network according to
    the config option 'connect' (see `connect/0`)
  """
  use GenServer
  require Logger
  @check_nodes_time 5000

  @doc """
    Tries to connect to a series of nodes

    Nodes are expected in the form name@domain or simply 'domain'

    We will fin all IPs associated with domain either as a A record or a SRV record
    Then it will try to connecto to name@ip1, name@ip2, etc., and, if a name is present
    in SRV record, using also that name

    If K8s is not registering the pod names in the service, but the A-B-C-D...,
    you need to provide the name, and it will be tested against all ips

    If it is registering the names, you only need the service
  """

  def find_nodes() do
    find_nodes = System.get_env("NK_CONNECT")
    find_nodes(find_nodes)
  end

  def find_nodes(nil), do: []
  def find_nodes([]), do: []

  def find_nodes(single) when is_binary(single),
    do: do_find_nodes([single], [])

  def find_nodes(list) when is_list(list), do: do_find_nodes(list, [])

  defp do_find_nodes([], nodes), do: nodes

  defp do_find_nodes([node | rest], nodes) when is_binary(node) do
    nodes =
      case String.split(node, "@") do
        [name, domain] ->
          case resolve_service(domain) do
            [] -> [{name, resolve_host(domain)}]
            list -> list
          end

        [domain] ->
          resolve_service(domain)
      end
      |> Enum.reduce(nodes, fn {name, ips}, acc2 ->
        acc2 ++ for(ip <- ips, do: "#{name}@#{ip}")
      end)

    do_find_nodes(rest, nodes)
  end

  def connect(), do: find_nodes() |> do_connect()

  def connect(connect), do: find_nodes(connect) |> do_connect()

  defp do_connect(list) do
    my_nodes = [node() | Node.list()]

    for node <- find_nodes(list) do
      node = String.to_atom(node)

      if not Enum.member?(my_nodes, node) do
        case Node.connect(node) do
          true ->
            IO.puts("CONNECTED to #{node}")

          _ ->
            :ok
        end
      end
    end

    :ok
  end

  def start_link([]),
    do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]) do
    # IO.puts("Cluster: #{inspect(self())}")
    Process.send_after(self(), :malla_connect_nodes, 5000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:malla_connect_nodes, state) do
    connect()
    Process.send_after(self(), :malla_connect_nodes, @check_nodes_time)
    {:noreply, state}
  end

  # def handle_cast({:set_runtime, pid, runtime}, state) do
  #   Livebook.Session.set_runtime(pid, runtime)
  #   {:noreply, state}
  # end

  # defp do_connect([]), do: :ok

  # defp do_connect([{name, ips} | rest]) do
  #   nodes = [node() | Node.list()]

  #   for ip <- ips do
  #     node = String.to_atom("#{name}@#{ip}")

  #     if not Enum.member?(nodes, node) do
  #       case Node.connect(node) do
  #         true ->
  #           IO.puts("CONNECTED to #{node}")

  #         _ ->
  #           # IO.puts("NOT CONNECTED to #{node}")
  #           :ok
  #       end
  #     end
  #   end

  #   do_connect(rest)
  # end

  # see problem on resolve_service
  @dialyzer {:no_match, resolve_host: 1}

  defp resolve_host(domain) do
    case :inet_res.getbyname(String.to_charlist(domain), :a) do
      {:ok, {:hostent, _, _, :inet, _, ips}} ->
        for(ip <- ips, do: to_string(:inet_parse.ntoa(ip)))

      _ ->
        []
    end
  end

  # It seems the spec for :inet_res.getbyname/2 is not correct
  # We also need to ignore resolve_service/3 and resolve_nodes/1
  # https://www.erlang.org/doc/man/dialyzer.html#type-warn_option
  @dialyzer {:no_match, resolve_service: 1}

  defp resolve_service(service) do
    case :inet_res.getbyname(String.to_charlist(service), :srv) do
      {:ok, {:hostent, _fullsrv, _list, :srv, _num_nodes, nodes}} ->
        resolve_service(nodes, [])

      o ->
        IO.puts("Error in resolve for #{service}: #{inspect(o)}")
        []
    end
  end

  @dialyzer {:no_unused, resolve_service: 2}
  defp resolve_service([], acc), do: acc

  defp resolve_service([{_, _, _, name} | rest], acc) do
    [node, _] = String.split(to_string(name), ".", parts: 2)
    ips = resolve_host(to_string(name))
    # IO.puts("CONNECTING TO #{inspect node}: #{name} #{inspect ips}")
    resolve_service(rest, [{node, ips} | acc])
  end
end
