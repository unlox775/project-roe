defmodule CommandLineTest do
  use ExUnit.Case, async: false
  import Mock
  import ExUnit.CaptureIO

  alias Pidge.Harness.CommandLine
  alias Pidge.Runtime.SessionState

  @simple_ast_contents [
    %{id: nil, seq: "00001", params: %{conversation_id: :elmer}, method: :context_create_conversation}
  ]
  @input_req_ast_contents [
    %{id: "elmer/read_json_example", seq: "00001", params: %{format: "json", prompt: "elmer/read_json_example", conversation_id: "elmer", schema: {:__aliases__, [line: 3], [:Plot]}}, method: :ai_object_extract}
  ]
  @base_opts %{ verbosity: 1, session: "test" }

  setup_with_mocks([
    {Pidge.WebClient, [:passthrough], send_and_wait_for_response: fn _,_ -> {:ok, %{"body" => "asdf"}} end},
    {Pidge.Run, [:passthrough], compile_template: fn _ -> {:ok, "asdf"} end},
    {Pidge.Runtime.SessionState, [:passthrough], get_current_state: fn _ -> {:ok, %{}} end},
    {System, [], [halt: fn code -> code end]}
  ]) do
    :ok
  end

  describe "parse_opts/1" do
    test "parses --help option" do
      # capture the System.exit(0) call
      output = capture_io(fn -> CommandLine.parse_opts(["--help"]) end)
      assert "Usage: pidge run [OPTIONS]"<>_ = output
    end

    test "parses --input and verbosity options" do
      expected_opts = %{
        input: "Some text",
        verbosity: 3
      }
      assert CommandLine.parse_opts(["--input", "Some text", "-vvv"]) == expected_opts
    end
  end

  test "run/1 with empty args" do
    wipe_base_session()

    # this uses the simple AST from above
    assert capture_io(fn ->
      CommandLine.private__run(@base_opts, %{
        pidge_code: %{main: @simple_ast_contents},
        local_function_files: %{},
        prompt_files: %{}
    })
    end) == "Pidge Execution complete.\n"
  end

  test "run/2 with mocked :required_input_callback and re-call" do
    wipe_base_session()

    with_mock(CommandLine, [:passthrough], read_stdin_input: fn _,opts -> Map.put(opts, :input, "asdf") end) do
      capture_io(fn ->
        assert CommandLine.private__run(@base_opts, %{
          pidge_code: %{main: @input_req_ast_contents},
          local_function_files: %{},
          prompt_files: %{}
        }) == {:last}
      end)
      assert_called CommandLine.read_stdin_input(:_,:_)
    end
  end

  def wipe_base_session() do
    {:ok, sessionstate_pid} = SessionState.start_link(@base_opts.session)
    SessionState.wipe()
    SessionState.stop(sessionstate_pid)
  end
end
