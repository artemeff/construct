defmodule Struct do
  defmacro __using__(opts \\ []) do
    quote do
      import Struct, only: [structure: 1]

      def make(params \\ %{}, opts \\ []) do
        Struct.Cast.make(__MODULE__, params, Keyword.merge(opts, unquote(opts)))
      end

      def make!(params \\ %{}, opts \\ []) do
        case make(params, opts) do
          {:ok, struct} -> struct
          {:error, reason} -> raise Struct.MakeError, %{reason: reason, params: params}
        end
      end

      def cast(params, opts \\ []) do
        make(params, opts)
      end

      defoverridable make: 2
    end
  end

  defmacro structure([do: block]) do
    quote do
      import Struct

      Module.register_attribute(__MODULE__, :fields, accumulate: true)
      Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)

      unquote(block)

      struct_fields = Enum.reverse(@struct_fields)
      fields = Enum.reverse(@fields)

      Module.eval_quoted __ENV__, [
        Struct.__defstruct__(struct_fields),
        Struct.__types__(fields)]
    end
  end

  defmacro include(module) do
    quote do
      module = unquote(module)

      unless Code.ensure_compiled?(module) do
        raise Struct.DefinitionError, "undefined module #{module}"
      end

      unless function_exported?(module, :__structure__, 1) do
        raise Struct.DefinitionError, "provided #{module} is not Struct module"
      end

      type_defs = module.__structure__(:types)

      Enum.each(type_defs, fn({name, _type}) ->
        {type, opts} = module.__structure__(:type, name)
        Struct.__field__(__MODULE__, name, type, opts)
      end)
    end
  end

  defmacro field(name, definition \\ :string, opts \\ [])
  defmacro field(name, opts, [do: _] = contents) do
    __make_nested_field__(name, contents, opts)
  end
  defmacro field(name, [do: _] = contents, _opts) do
    __make_nested_field__(name, contents, [])
  end
  defmacro field(name, type, opts) do
    quote do
      Struct.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  defp __make_nested_field__(name, contents, opts) do
    check_field_name!(name)

    nested_module_name = String.to_atom(Macro.camelize(Atom.to_string(name)))

    quote do
      current_module_name_ast =
        __MODULE__
        |> Atom.to_string()
        |> String.split(".")
        |> Enum.map(&String.to_atom/1)

      current_module_ast =
        {:__aliases__, [alias: false], current_module_name_ast ++ [unquote(nested_module_name)]}
        |> Macro.expand(__ENV__)

      defmodule current_module_ast do
        use Struct
        structure do: unquote(contents)
      end

      Struct.__field__(__MODULE__, unquote(name), current_module_ast, unquote(opts))
    end
  end

  @doc false
  def __defstruct__(struct_fields) do
    quote do
      defstruct unquote(Macro.escape(struct_fields))
    end
  end

  @doc false
  def __types__(fields) do
    quoted =
      Enum.map(fields, fn({name, type, opts}) ->
        quote do
          def __structure__(:type, unquote(name)) do
            {unquote(Macro.escape(type)), unquote(Macro.escape(opts))}
          end
        end
      end)

    types =
      fields
      |> Enum.into(%{}, fn({name, type, _default}) -> {name, type} end)
      |> Macro.escape

    quote do
      def __structure__(:types), do: unquote(types)
      unquote(quoted)
      def __structure__(:type, _), do: nil
    end
  end

  @doc false
  def __field__(mod, name, type, opts) do
    check_field_name!(name)
    check_type!(type)

    Module.put_attribute(mod, :fields, {name, type, opts})
    Module.put_attribute(mod, :struct_fields, {name, default_for_struct(opts)})
  end

  def default_for_struct(opts) do
    check_default!(Keyword.get(opts, :default))
  end

  defp check_type!({:array, type}) do
    unless Struct.Type.primitive?(type), do: check_type_complex!(type)
  end
  defp check_type!({:map, type}) do
    unless Struct.Type.primitive?(type), do: check_type_complex!(type)
  end
  defp check_type!({complex, _}) do
    raise Struct.DefinitionError, "undefined complex type #{inspect(complex)}"
  end
  defp check_type!(type_list) when is_list(type_list) do
    Enum.each(type_list, &check_type!/1)
  end
  defp check_type!(type) do
    unless Struct.Type.primitive?(type), do: check_type_complex!(type)
  end

  defp check_type_complex!(module) do
    unless Code.ensure_compiled?(module) do
      raise Struct.DefinitionError, "undefined module #{module}"
    end

    unless function_exported?(module, :cast, 1) do
      raise Struct.DefinitionError, "undefined function cast/1 for #{module}"
    end
  end

  defp check_field_name!(name) when is_atom(name) do
    :ok
  end
  defp check_field_name!(name) do
    raise Struct.DefinitionError, "expected atom for field name, got `#{inspect(name)}`"
  end

  defp check_default!(default) when is_function(default) do
    raise Struct.DefinitionError, "default value cannot to be a function"
  end
  defp check_default!(default) do
    default
  end
end
