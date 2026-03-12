# **pidge**

## What Pidge Is — Legacy and Vision

Pidge is a programming language and runtime for **agentic flows** built in the summer of 2023. It was created before the term "agentic" was commonplace, before multi-agent systems became mainstream, and while most people were still pasting prompts into ChatGPT's web interface.

### The World It Was Built In

When this was written, GPT-4 had just launched (March 2023). LangChain was gaining traction but function calling had only landed in June 2023. The dominant way to use AI was still: open a chat, paste, copy, paste somewhere else. Pidge was built by someone doing exactly that—with a bookmarklet to automate the copy-paste—because there was no better option at the time.

### Core Architecture: Everything Is a DAG

The fundamental building block of Pidge is the **directed acyclic graph (DAG)**. Data and control flow pipe from one step to the next. The component—the `ai_prompt`, the `ai_pipethru`, the human input step—is the node; the pipe `|>` is the edge. The compiler turns `.pj` source into a compiled composite (`.pjc`): a fully resolved DAG of all steps baked together.

The language is valid Elixir for parsing purposes. The compiler uses the Elixir parser, transforms the AST into Pidge semantics, and emits `.pjc` files that the runtime executes. It was never meant to run as Elixir.

### Human in the Loop as a First-Class Participant

What Pidge does that still hasn't been replicated well elsewhere: **humans are treated as just another participant** in the flow. Not as a special "approval gate" or "feedback loop"—but as a node in the same pipeline. The human can provide input, step in, override, and jump around (`--from_step`) within an ordered process. The routine remains semi-deterministic because the DAG defines the structure; humans choose where they stand in it.

This is different from bolting a human step onto an agentic workflow. Here, the human and the AI agents share the same abstraction.

### What It Presaged

- **Multi-agent flows**: Different agents (e.g., `:bard` and `:whip` in the example app) run in sequence, each with its own conversation and role. This presages what later multi-agent and agentic frameworks made commonplace—multiple agents talking to each other.
- **Agentic structure**: The flow is declarative. You define a pipeline; the runtime runs it. No ad-hoc orchestration code.

### Why It Paused

Development halted when life moved on. But before that, ChatGPT added JavaScript detection that broke the bookmarklet—the glue that injected prompts into the web UI and scraped responses back. The runtime, compiler, and language work; the *bridge* to the LLM was a fragile hack. Pidge was never completed, but the concepts are still under-explored.

### Minimum to Make It Usable Again

The bookmarklet path has been replaced with direct OpenAI API calls. Set `OPENAI_API_KEY` in your environment, then from an app directory (e.g. `asdf/`):

1. **First run** (no human input):  
   `pidge run --session YOUR_SESSION`  
   When a step needs human input, the process prints the exact command to rejoin.

2. **Rejoin** with your answer:  
   `pidge run --session YOUR_SESSION --from_step STEP_ID --human_input "your input"`  
   Use the same session so conversation history and state stay in sync.

LLM conversation history is stored per session in `release/{session}_llm.json`. See [docs/TODO.md](docs/TODO.md) for more detail and optional improvements.

---

## Setup and Usage

This section covers how to set up, compile, and run Pidge. Note: the bookmarklet that communicated with ChatGPT's web interface is deprecated and no longer works; direct LLM integration is required (see docs/TODO.md).

### Prerequisites

- Elixir version 1.15 or higher.
- Erlang (compatible with your Elixir version). Tested with Erlang 24 and 26.

### Installation

1. Clone the pidge git repository.
2. Ensure you have the aforementioned prerequisites installed.
3. Navigate to the root directory of the pidge repository.
4. Run `make build` to compile the app. This will create an executable binary named `pidge` in the `release/` directory.
5. You can either:
    - Move the `pidge` binary from `release/` to a directory in your system's PATH, e.g., `/usr/local/bin/`, or
    - Add the path to the `release/` directory to your system's PATH.

### Getting Started

1. **Create a New App**: 
   ```bash
   pidge new [app-name]
   ```
   This command initializes a new pidge app in a directory named `[app-name]`. The basic structure includes:
   - A `src/` directory.
   - Inside `src/`, a `prompt/` directory containing folders for each AI conversation. The default template has two conversations named `bird` and `insight`.
   - A main file: `main.pj`.
   - Conversation templates with `.pjt` extensions.

2. **Compile the App**: 
   ```bash
   pidge compile
   ```

3. **Run the App**:

To run your pidge app, use the following command:

```bash
pidge run [options]
```

Here are the available command-line switches for the `run` command:

- **Verbosity**:
    - `-v` or `--verbose`: Increases the level of output verbosity. 
    - Multiple verbosity levels can be set by adding more `v` characters (e.g., `-vvvv`).

- **Help**: 
    - `-h` or `--help`: Displays the help content, providing an overview of the available options.

- **Session**:
    - `--session [session-name]`: Defines the session name for your app. This session name is crucial, especially when using the bookmarklet. It serves as the identifier for the session. The name should not contain spaces or special characters, and it will be automatically converted to lowercase. For instance, "ElvisStoryGen2023" is an acceptable session name.

- **Input**:
    - `--input "[string]"`: Allows users to pass in a string input directly from the command line.
    - Alternatively, if no input is provided and the app expects one, the program will pause and wait for the user to provide the input via standard input.

- **Human Input**:
    - `--human_input "[string]"` or `--human-input "[string]"`: Used to provide human-specific input, suggestions, or ideas. This is distinct from the regular input and is designed to capture insights from the user.

- **Starting from a Specific Step**:
    - `--from_step [step-name]`: Instructs pidge to commence the execution from a specified step, rather than from the beginning. This is particularly useful given pidge's unique design which allows for "human in the loop" interactions, pausing and resuming as required. Each step is named after its corresponding AI prompt.  For example an AI step using the prompt file `src/pidge/bird/03_revision.pjt` would have a step name of `bird/03_revision`. The control flow, inclusive of loops and conditions, appends to this step name, allowing precise identification of the desired execution point, even if nested several layers deep.  NOTE: this literally jumps to that step, using the current in-memory state.  It does not re-run any previous steps, so if your previous step defined a variable that is needed, that variable will show up as empty when your step tries to access it.

4. **Quick Compile & Run**:
   If you're iterating rapidly, you can use:
   ```bash
   pidge go [run-options]
   ```
   This command first compiles and then immediately runs your app.

### Bookmarklet (Deprecated)

The bookmarklet once bridged Pidge to ChatGPT's web UI. It no longer works due to JavaScript detection changes. See [docs/TODO.md](docs/TODO.md) for replacing it with direct LLM API calls.

1. Run `make bookmarklet_compile` to minify the bookmarklet and write it to `release/bookmarklet.txt`.
2. Create a bookmark and paste the code as its URL.
3. Navigate to a ChatGPT conversation and click the bookmark; input a session like `bird-aaa`. *This path is broken in current ChatGPT.*

### Roadmap

- Replace the bookmarklet with direct LLM API integration (see docs/TODO.md).
- Further documentation and packaging.

### Conclusion

This guide provides the basic steps to get started with pidge. For a deeper dive into the language syntax and the underlying theory, please refer to our detailed documentation (coming soon).