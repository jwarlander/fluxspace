alias Fluxspace.GenSync

defmodule Fluxspace.Entity do
  @moduledoc """
  Represents an Entity, which wraps a GenSync and provides some
  convenience functions for interacting with it.
  """

  defstruct uuid: "", attributes: %{}

  use GenSync

  alias Fluxspace.{Entity, Radio, Attribute}

  @doc """
  Gives you an Entity.
  """
  def start, do: start(UUID.uuid4())
  def start(entity_uuid), do: start(entity_uuid, %{})
  def start(entity_uuid, attributes) when is_map(attributes) do
    {:ok, ^entity_uuid, pid} = start_plain(entity_uuid, attributes)
    {:ok, entity_uuid, pid}
  end

  @doc """
  Gives you a plain entity with a Radio.Behaviour and an Attribute.Behaviour.
  """
  def start_plain(entity_uuid \\ UUID.uuid4(), attributes \\ %{}) do
    {:ok, pid} = GenSync.start_link(%Entity{uuid: entity_uuid, attributes: attributes})

    :gproc.reg_other({:n, :l, entity_uuid}, pid)
    pid |> Radio.register
    pid |> Attribute.register

    {:ok, entity_uuid, pid}
  end

  @doc """
  Returns a PID of an entity when given its UUID.
  """
  def locate_pid(entity_uuid) do
    try do
      pid = :gproc.lookup_pid({:n, :l, entity_uuid})
      {:ok, pid}
    rescue
      ArgumentError -> :error
    end
  end

  @doc """
  Returns a PID of an entity when given its UUID, or throws an error.
  """
  def locate_pid!(entity_uuid) do
    try do
      :gproc.lookup_pid({:n, :l, entity_uuid})
    rescue
      ArgumentError -> raise "Entity not found: #{entity_uuid}"
    end
  end

  @doc """
  Checks whether or not this entity UUID exists or not.
  """
  def exists?(entity_uuid) do
    with {:ok, _} <- locate_pid(entity_uuid) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Kills an Entity.
  """
  def kill(entity_pid) when is_pid(entity_pid) do
    entity_pid |> GenServer.stop()
  end

  def kill(entity_uuid) do
    with {:ok, pid} <- locate_pid(entity_uuid) do
      kill(pid)
    else
      _ -> :error
    end
  end

  @doc """
  Gets the entire entity state.
  """
  def get_state(entity_pid) when is_pid(entity_pid) do
    entity_pid |> :sys.get_state()
  end

  def get_state(entity_uuid) do
    with {:ok, pid} <- locate_pid(entity_uuid) do
      get_state(pid)
    else
      _ -> :error
    end
  end

  # ---
  # Behaviour API
  # ---

  @doc """
  Calls a Behaviour on an Entity.
  """
  def call_behaviour(
    entity,
    behaviour,
    message
  ) when is_pid(entity) and is_atom(behaviour) do
    GenSync.call(entity, behaviour, message)
  end

  def call_behaviour(entity_uuid, behaviour, message) do
    entity_uuid |> locate_pid_and_execute(&call_behaviour(&1, behaviour, message))
  end

  @doc """
  Checks if an Entity has a certain Behaviour.
  """
  def has_behaviour?(
    entity,
    behaviour
  ) when is_pid(entity) and is_atom(behaviour) do
    GenSync.has_handler?(entity, behaviour)
  end

  def has_behaviour?(entity_uuid, behaviour) do
    entity_uuid |> locate_pid_and_execute(&has_behaviour?(&1, behaviour))
  end

  @doc """
  Adds a Behaviour to an Entity.
  """
  def put_behaviour(
    entity,
    behaviour,
    args
  ) when is_pid(entity) and is_atom(behaviour) do
   GenSync.put_handler(entity, behaviour, args)
  end

  def put_behaviour(entity_uuid, behaviour, args) do
    entity_uuid |> locate_pid_and_execute(&put_behaviour(&1, behaviour, args))
  end

  @doc """
  Removes a Behaviour from an Entity.
  """
  def remove_behaviour(
    entity,
    behaviour
  ) when is_pid(entity) and is_atom(behaviour) do
    GenSync.remove_handler(entity, behaviour)
  end

  def remove_behaviour(entity_uuid, behaviour) do
    entity_uuid |> locate_pid_and_execute(&remove_behaviour(&1, behaviour))
  end

  # ---
  # Private
  # ---

  defp locate_pid_and_execute(entity_uuid, fun) do
    try do
      pid = :gproc.lookup_pid({:n, :l, entity_uuid})
      fun.(pid)
    rescue
      ArgumentError -> :error
    end
  end

  defmodule Behaviour do
    defmacro __using__(_) do
      quote do
        use GenSync
        alias Fluxspace.Entity

        def init(entity, _args), do: {:ok, entity}

        def has_attribute?(%Entity{attributes: attrs}, attribute_type) when is_atom(attribute_type),
        do: Map.has_key?(attrs, attribute_type)

        def fetch_attribute(%Entity{attributes: attrs}, attribute_type) when is_atom(attribute_type),
        do: Map.fetch(attrs, attribute_type)

        def fetch_attribute!(%Entity{attributes: attrs}, attribute_type) when is_atom(attribute_type),
        do: Map.fetch!(attrs, attribute_type)

        def get_attribute(%Entity{attributes: attrs}, attribute_type) when is_atom(attribute_type),
        do: Map.get(attrs, attribute_type)

        def take_attributes(%Entity{attributes: attrs}, attribute_types) when is_list(attribute_types),
        do: Map.take(attrs, attribute_types)

        def put_attribute(%Entity{attributes: attrs} = entity, %{__struct__: attribute_type} = attribute),
        do: %Entity{entity | attributes: Map.put(attrs, attribute_type, attribute)}

        def update_attribute(%Entity{attributes: attrs} = entity, attribute_type, modifier)
        when is_atom(attribute_type) and is_function(modifier, 1) do
          case Map.has_key?(attrs, attribute_type) do
            true -> %Entity{entity | attributes: Map.update!(attrs, attribute_type, modifier)}
            false -> entity
          end
        end

        def remove_attribute(%Entity{attributes: attrs} = entity, attribute_type) when is_atom(attribute_type),
        do: %Entity{entity | attributes: Map.delete(attrs, attribute_type)}

        def attribute_transaction(%Entity{attributes: attrs} = entity, modifier) when is_function(modifier, 1),
        do: %Entity{entity | attributes: modifier.(attrs)}

        def handle_call(:kill, entity) do
          {:stop_process, :normal, :ok, entity}
        end

        def handle_event(:kill, entity) do
          {:stop_process, :normal, entity}
        end

        defoverridable [init: 2]
      end
    end
  end
end
