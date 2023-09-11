# **pidge**

pidge is a powerful tool that aids in creating and managing AI-driven conversation projects. In this README, we provide a brief overview of how to set up, compile, and use pidge along with its associated development bookmarklet.

## **Prerequisites**

- Elixir version 1.15 or higher.
- Erlang (compatible with your Elixir version). Tested with Erlang 24 and 26.

## **Installation**

1. Clone the pidge git repository.
2. Ensure you have the aforementioned prerequisites installed.
3. Navigate to the root directory of the pidge repository.
4. Run `make build` to compile the project. This will create an executable binary named `pidge` in the `release/` directory.
5. You can either:
    - Move the `pidge` binary from `release/` to a directory in your system's PATH, e.g., `/usr/local/bin/`, or
    - Add the path to the `release/` directory to your system's PATH.

## **Getting Started with pidge**

1. **Create a New Project**: 
   ```bash
   pidge new [project-name]
   ```
   This command initializes a new pidge project in a directory named `[project-name]`. The basic structure includes:
   - A `src/` directory.
   - Inside `src/`, a `prompt/` directory containing folders for each AI conversation. The default template has two conversations named `bird` and `insight`.
   - A main file: `main.pj`.
   - Conversation templates with `.pjt` extensions.

2. **Compile the Project**: 
   ```bash
   pidge compile
   ```

3. **Run the Project**:

To run your pidge project, use the following command:

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
    - `--session [session-name]`: Defines the session name for your project. This session name is crucial, especially when using the bookmarklet. It serves as the identifier for the session. The name should not contain spaces or special characters, and it will be automatically converted to lowercase. For instance, "ElvisStoryGen2023" is an acceptable session name.

- **Input**:
    - `--input "[string]"`: Allows users to pass in a string input directly from the command line.
    - Alternatively, if no input is provided and the project expects one, the program will pause and wait for the user to provide the input via standard input.

- **Human Input**:
    - `--human_input "[string]"` or `--human-input "[string]"`: Used to provide human-specific input, suggestions, or ideas. This is distinct from the regular input and is designed to capture insights from the user.

- **Starting from a Specific Step**:
    - `--from_step [step-name]`: Instructs pidge to commence the execution from a specified step, rather than from the beginning. This is particularly useful given pidge's unique design which allows for "human in the loop" interactions, pausing and resuming as required. Each step is named after its corresponding AI prompt.  For example an AI step using the prompt file `src/pidge/bird/03_revision.pjt` would have a step name of `bird/03_revision`. The control flow, inclusive of loops and conditions, appends to this step name, allowing precise identification of the desired execution point, even if nested several layers deep.  NOTE: this literally jumps to that step, using the current in-memory state.  It does not re-run any previous steps, so if your previous step defined a variable that is needed, that variable will show up as empty when your step tries to access it.

4. **Quick Compile & Run**:
   If you're iterating rapidly, you can use:
   ```bash
   pidge go [run-options]
   ```
   This command first compiles and then immediately runs your project.

## **Bookmarklet**

1. Run `make bookmarklet_compile` to minify the JavaScript code for the bookmarklet, and write it to `release/bookmarklet.txt`. This action will also copy the minified code to your clipboard (Mac only).
2. Create a new bookmark in your browser and paste the copied code as its URL.
3. Navigate to a ChatGPT conversation and click the bookmark. When prompted, input a session in the format `[conversation-name]-[session-name]`, e.g., `bird-aaa`.

## **Future Roadmap**

- Replace the bookmarklet with a more robust Chrome extension.
- Further enhance pidge with additional functionalities and features.
- Work towards packaging and distribution for various platforms.

## **Conclusion**

This guide provides the basic steps to get started with pidge. For a deeper dive into the language syntax and the underlying theory, please refer to our detailed documentation (coming soon).