defmodule Nk.Node do
  @moduledoc """
    Maintains a list of all services on the network, along
    with the status of each one

    Each 5 secs, re-checks all services on the network and asks status

    Each one in monitored.
    For those running, pids and vsn's are stored, to be retrieved using get_instances/1

    The calling order of services is randomized on each call.
    If the service is running locally, it will be the first on the list.
  """
  use GenServer

  @type state :: __MODULE__
  alias __MODULE__, as: State

  require Logger

  @check_services_time 10000
  @rpc_timeout 30000

  @type srv_id :: atom()

  ## ===================================================================
  ## API
  ## ===================================================================

  @type instance_status ::
          {node, metadata :: map()}

  @doc """
    Gets all nodes and metadata implementing a specific service with status ':running'

    If the local node is available, it will be first
    The rest will shuffle every 5 seconds
  """

  @spec get_instances(srv_id) :: [instance_status]
  def get_instances(srv_id),
    do: GenServer.call(__MODULE__, {:get_instances, srv_id}, 5000)

  @doc """
    Gets all nodes implementing a specific service

    If the local node is available, it will be first
    The rest will shuffle every 5 seconds
  """
  @spec get_nodes(srv_id) :: [node()]
  def get_nodes(srv_id),
    do: GenServer.call(__MODULE__, {:get_nodes, srv_id}, 5000)

  def get_services(), do: GenServer.call(__MODULE__, :get_services)

  # if timeout=0, means 'dont wait any answer'
  @type call_opt ::
          {:timeout, timeout}
          | {:srv_id, srv_id}
          | {:nodes, [node()]}

  @doc """
    Launches a request to call a callback defined on a remote service

    It will call function 'cb' on remote Service's module.
    This function will call in turn requested function on service's module, after changing process's group

    Usually, this function will be a callback defined with defcallback.
    If timeout=0, a 'cast' will be performed instead of a 'call'

    It uses `get_nodes/1` to find pids, and launches the request to the first one.
    Only if error is `{:error, :service_not_available}` from remote, the next one is tried.

    Returns `{:error, :service_not_available}` if we exhaust the instances or none is available.
    Returns `{:error, {:malla_rpc_error, {term, text}}}` if an exception is produced remotely or in :erpc.call
  """

  @spec cb(srv_id, atom, list, [call_opt]) ::
          {:error, :service_not_available | {:malla_rpc_error, {term(), String.t()}}} | term

  def cb(srv_id, fun, args, opts \\ []),
    do: call(srv_id, :cb, [fun, args, opts], [{:srv_id, srv_id} | opts])

  def cb2(srv_id, fun, args, opts \\ []),
    do: call(srv_id, :malla_cb_in, [fun, args, opts], [{:srv_id, srv_id} | opts])

  @doc """
    Launches an asynchronous request to all nodes implementing a service,
    calling a function 'cb' on each remote Service's module.

    This function will itself call request function on same module, after changing process's group
    Usually, this function will be a callback defined with defcallback.
  """

  @spec cb_all_sync(srv_id, atom, list, [call_opt]) :: [term]

  def cb_all_sync(srv_id, fun, args, opts \\ []) do
    for node <- get_nodes(srv_id) do
      do_call_node(node, srv_id, :cb, [fun, args, opts], opts)
    end
  end

  @doc """
    Launches an asynchronous request to all nodes implementing a service,
    calling a function 'cb' on each remote Service's module.

    This function will itself call request function on same module, after changing process's group
    Usually, this function will be a callback defined with defcallback.
  """

  @spec cb_all_async(srv_id, atom, list, [call_opt]) :: :ok

  def cb_all_async(srv_id, fun, args, opts \\ []) do
    for node <- get_nodes(srv_id) do
      :erpc.cast(node, srv_id, :cb, [fun, args, opts])
    end

    :ok
  end

  @doc """
    Launches a call to a remote node

    A node list is obteined from `nodes` parameter, or, if not present,
    a srv_id must be obtained from `srv_id` parameter or process dictionary,
    and the nodes running the service will we used.

    First node will be called, and, only if it returns `{:error, :service_not_available}` from remote,
    the next one is tried.

    Returns `{:error, :service_not_available}` if we exhaust the instances or none is available.
    Returns `{:error, {:malla_rpc_error, {term, text}}}` if an exception is produced remotely or in :erpc.call
  """

  @spec call(module, atom, list, [call_opt]) ::
          {:error, :service_not_available | {:malla_rpc_error, {term(), String.t()}}} | term

  def call(mod, fun, args, opts \\ []) do
    nodes =
      case Keyword.get(opts, :nodes) do
        nil ->
          case opts[:service_id] do
            nil -> {:error, :service_missing}
            srv_id -> get_nodes(srv_id)
          end

        nodes ->
          nodes
      end

    do_call(nodes, mod, fun, args, opts)
  end

  defp do_call([], _mod, _fun, _args, _opts),
    do: {:error, :service_not_available}

  defp do_call([node | rest], mod, fun, args, opts) do
    case do_call_node(node, mod, fun, args, opts) do
      {:error, :service_not_available} ->
        case rest do
          [] ->
            Logger.warning("Service '#{inspect(mod)}' not available at #{node}")

          _ ->
            Logger.warning("Service '#{inspect(mod)}' not available at #{node}, trying next")
        end

        do_call(rest, mod, fun, args, opts)

      other ->
        other
    end
  end

  # https://erlang.org/doc/man/erpc.html#call-4
  defp do_call_node(node, mod, fun, args, opts) do
    try do
      case Keyword.get(opts, :timeout, @rpc_timeout) do
        0 ->
          :erpc.cast(node, mod, fun, args)

        timeout ->
          # Logger.debug("CALL RPC REMOTE #{inspect({node, mod, fun, args, timeout})}")
          result = :erpc.call(node, mod, fun, args, timeout)
          # Logger.debug("RPC REMOTE RESULT #{inspect result}")
          result
      end
    rescue
      e ->
        text = Exception.format(:error, e, __STACKTRACE__)
        Logger.warning("MallaNode RPC Exception: #{inspect(e)} #{text}")
        {:error, {:malla_rpc_error, {e, text}}}
    catch
      :exit, do_exit ->
        Logger.warning("MallaNode RPC CATCH: #{inspect(do_exit)}")
        {:error, {:malla_rpc_error, {do_exit, inspect(do_exit)}}}
    end
  end

  ## ===================================================================
  ## GenServer
  ## ===================================================================

  def start_link([]), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @type t :: %State{
          # current service_info
          services_info: %{pid() => {srv_id, meta: map()}},
          # all detected ids, ever
          instances: %{srv_id => [node]}
        }

  defstruct [:services_info, :instances]

  @impl true
  def init([]) do
    :pg.start_link(Malla.Services2)
    :ok = :pg.join(Malla.Services2, __MODULE__, self())
    state = %State{services_info: %{}, instances: %{}}
    Process.send_after(self(), :check_services, 1000)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_services, _from, %State{services_info: info} = state) do
    {:reply, info, state}
  end

  def handle_call({:get_instances, srv_id}, _from, %State{instances: instances} = state) do
    {:reply, Map.get(instances, srv_id, []), state}
  end

  def handle_call({:get_nodes, srv_id}, _from, %State{instances: instances} = state) do
    nodes = for {node, _} <- Map.get(instances, srv_id, []), do: node
    {:reply, nodes, state}
  end

  @impl true
  def handle_cast({:set_service_info, true, info}, state) do
    %State{services_info: services_info} = state
    %{id: srv_id, pid: pid, meta: meta} = info
    if Map.get(services_info, pid) == nil, do: Process.monitor(pid)
    services_info = Map.put(services_info, pid, {srv_id, meta})
    maybe_make_module(srv_id, meta)
    # recalculate to randomize services
    state = compute_services(%State{state | services_info: services_info})
    {:noreply, state}
  end

  def handle_cast({:set_service_info, false, info}, state) do
    %State{services_info: services_info} = state
    %{pid: pid} = info
    services_info = Map.delete(services_info, pid)
    state = compute_services(%State{state | services_info: services_info})
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_services, state) do
    check_services()
    Process.send_after(self(), :check_services, @check_services_time)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    %State{services_info: services_info} = state

    case Map.get(services_info, pid) do
      nil ->
        # It already reported as down
        {:noreply, state}

      {srv_id, _meta} ->
        Logger.notice("Remote service #{inspect(srv_id)} is down on #{inspect(node(pid))}")
        services_info = Map.delete(services_info, pid)
        state = %State{state | services_info: services_info}
        {:noreply, compute_services(state)}
    end
  end

  ## ===================================================================
  ## Internal
  ## ===================================================================

  @type service_info :: %{id: srv_id, pid: pid(), meta: map}

  # For each service instance detected on the network,
  # launches a process to ask for status and cast back
  # Each service can only last the duration of the call

  defp check_services() do
    fun = fn pid ->
      case GenServer.call(pid, :get_running_info, 5000) do
        {:ok, {running, info}} -> GenServer.cast(__MODULE__, {:set_service_info, running, info})
        _ -> :ok
      end
    end

    all_pids = :pg.get_members(Malla.Services2, :all)
    Enum.each(all_pids, fn pid -> spawn(fn -> fun.(pid) end) end)
  end

  # Finds running services and stores pid and vsn in config to
  # be retrieved by get_instances/1
  defp compute_services(state) do
    %State{services_info: services_info, instances: instances} = state

    # lets suppose all previous detected services are now empty (no implementations on network)
    base = for id <- Map.keys(instances), do: {id, []}, into: %{}

    instances =
      services_info
      |> Enum.reduce(base, fn {pid, {srv_id, meta}}, acc ->
        prev = Map.get(acc, srv_id, [])
        Map.put(acc, srv_id, [{node(pid), Map.put(meta, :pid, pid)} | prev])
      end)
      |> Enum.map(fn {id, list} ->
        # if the local node is on the list, put it the first
        list =
          case List.keytake(list, node(), 0) do
            {{_node, meta}, rest} -> [{node(), meta} | rand(rest)]
            nil -> rand(list)
          end

        {id, list}
      end)
      |> Map.new()

    %State{state | instances: instances}
  end

  defp rand([]), do: []
  defp rand([single]), do: [single]
  defp rand(list), do: Enum.shuffle(list)

  _ = """
   For each detected service, we create a module called '<SrvId>'
   On it, a function is added for each callback defined in remote service.

   When calling this functions, if no caller srv_id is detected,
   a call will be made to Nk.Node.cb/3

   If a service is detected, callback service_cb_out/4 will be called.
   Default implementation is again calling Nk.Node.cb/4
  """

  defp maybe_make_module(srv_id, %{callbacks: callbacks}) do
    if function_exported?(srv_id, :__malla_node_callbacks, 0) do
      # Module was already created by us
      case apply(srv_id, :__malla_node_callbacks, []) do
        ^callbacks -> :ok
        _ -> do_make_module(srv_id, callbacks)
      end
    else
      if not function_exported?(srv_id, :__info__, 1) do
        # let's make sure the original module is not there
        # because the service is running locally
        do_make_module(srv_id, callbacks)
      end
    end
  end

  # still not implemented for this module
  defp maybe_make_module(_srv_id, _), do: :ok

  defp do_make_module(srv_id, callbacks) do
    contents =
      quote do
        # @srv_id unquote(srv_id)
        @callbacks unquote(Macro.escape(callbacks))
        def __malla_node_callbacks(), do: @callbacks
        unquote(Nk.Node.make_callbacks())
      end

    :code.purge(srv_id)
    :code.delete(srv_id)
    {:module, _, _bin, _} = Module.create(srv_id, contents, Macro.Env.location(__ENV__))
  end

  def make_callbacks() do
    quote bind_quoted: [] do
      for {name, arity} <- @callbacks do
        args = Macro.generate_arguments(arity, __MODULE__)

        def unquote(name)(unquote_splicing(args)) do
          # if we find a local srv_id, call service_cb_out/4
          # otherwise call directly
          case Process.get(:malla_service_id) do
            nil ->
              Nk.Node.cb2(__MODULE__, unquote(name), unquote(args), [])

            caller_srv_id ->
              caller_srv_id.service_cb_out(__MODULE__, unquote(name), unquote(args), [])
          end

          # IO.puts("#{unquote(name)} #{Kernel.inspect(unquote_splicing(args))}")
          # unquote(module1).unquote(fun_name)(unquote_splicing(args))
        end
      end
    end
  end
end
