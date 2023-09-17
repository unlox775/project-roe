defmodule Pidge.App.Loft do
  @doc """
  This is a regsitry as the primary access point for all Apps compiled assets.  This includes pidge code, local functions, and prompt files.

  It is made as a GenServer, so that in a running multi-tenant system, many apps can be loaded and unloaded during the lifetime of the system.
  """

  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def stop(pid), do: GenServer.stop(pid, :normal)

  @spec register_app(atom, String.t | map) :: :ok | {:error, any}
  def register_app(app_name, %{} = app), do: GenServer.call(__MODULE__, {:register_app, app_name, app})
  def register_app(app_name, app_path) do
    try do
      # Load the app's manifest JSON
      manifest_path = Path.join(app_path, "manifest.json")
      manifest = Jason.decode!(File.read!(manifest_path), keys: :atoms)

      # Get the list of pidge code files, and read them into a list of strings
      #   These are listed in the manifest.json file under pidge_code
      #   The values are code filenames, without the .pjc extension
      pidge_code = manifest.pidge_code |> Enum.reduce(%{}, fn filename, acc ->
        pidge_code_path = Path.join(app_path, "#{filename}.pjc")
        pidge_code = read_pidge_ast_from_raw_string(File.read!(pidge_code_path))
        Map.put(acc, String.to_atom(filename), pidge_code)
      end)

      # Get the list of local function files, and read them into a list of strings
      #   These are listed in the manifest.json file under local_function_files
      #   The values are code filenames, including extension and path name
      #   relative to the {app_path}/local_functions
      local_function_files = manifest.local_function_files |> Enum.reduce(%{}, fn filename, acc ->
        local_function_path = Path.join([app_path, "local_functions", filename])
        local_function = File.read!(local_function_path)
        Map.put(acc, filename, local_function)
      end)

      # Get the list of prompt files, and read them into a list of strings
      #   These are listed in the manifest.json file under prompt_files
      #   The values are code filenames, without the .pjt file extention,
      #   but they do have the path name relative to the {app_path}/prompts
      prompt_files = manifest.prompt_files |> Enum.reduce(%{}, fn filename, acc ->
        prompt_path = Path.join([app_path, "prompts", "#{filename}.pjt"])
        prompt = File.read!(prompt_path)
        Map.put(acc, filename, prompt)
      end)

      GenServer.call(__MODULE__, {:register_app, app_name, %{
        manifest: manifest,
        pidge_code: pidge_code,
        local_function_files: local_function_files,
        prompt_files: prompt_files
      }})
    rescue
      error -> {:error, error}
    end
  end

  @spec get_pidge_code(atom, atom) :: String.t
  def get_pidge_code(app_name, pidge_code_name) do
    GenServer.call(__MODULE__, {:get_pidge_code, app_name, pidge_code_name})
  end

  # NOTE: this function name here is without any file extension
  #   This is because at runtime, it won't know what language the local function is written in
  #   The return value will be a tuple of the language and the code
  @spec get_local_function(atom, String.t) :: {atom, String.t}
  def get_local_function(app_name, local_function_name) do
    GenServer.call(__MODULE__, {:get_local_function, app_name, local_function_name})
  end

  @spec get_prompt(atom, String.t) :: String.t
  def get_prompt(app_name, prompt_name) do
    GenServer.call(__MODULE__, {:get_prompt, app_name, prompt_name})
  end

  # Callbacks

  def init(state) do
    {:ok, state}
  end

  def handle_call({:register_app, app_name, app_data}, _from, state) do
    {:reply, :ok, Map.put(state, app_name, app_data)}
  end

  def handle_call({:get_pidge_code, app_name, pidge_code_name}, _from, state) do
    {:reply, state[app_name].pidge_code[pidge_code_name], state}
  end

  def handle_call({:get_local_function, app_name, local_function_name}, _from, state) do
    cond do
      Map.has_key?(state[app_name].local_function_files, "#{local_function_name}.ex.pjf") ->
        {:reply, {:elixir, state[app_name].local_function_files["#{local_function_name}.ex.pjf"]}, state}
      true -> raise "PIDGE: Local function file not found: #{local_function_name}"
    end
  end

  def handle_call({:get_prompt, app_name, prompt_name}, _from, state) do
    {:reply, state[app_name].prompt_files[prompt_name], state}
  end


  # Helper functions

  def read_pidge_ast_from_raw_string(code_str) do
    try do
      #  TBD - This is a VERY insecure placeholder until we have a real parser
      {[%{} | _] = pidge_ast, []} = Code.eval_string(code_str)
      pidge_ast
    rescue
      error -> raise "PIDGE: Error parsing pidge code: #{error}"
    end
  end
end
