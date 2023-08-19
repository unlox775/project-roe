defmodule Pidge.Project do
  def new_project(project_name) do
    create_directory(project_name)
    create_directory("#{project_name}/src")
    create_directory("#{project_name}/src/prompts")
    create_directory("#{project_name}/src/prompts/bird")
    create_directory("#{project_name}/src/prompts/insight")

    create_file("#{project_name}/src/main.pj", main_pj_content())
    create_file("#{project_name}/src/prompts/bird/01_example.pjt", example_pjt_content())
    create_file("#{project_name}/src/prompts/insight/02_critique.pjt", critique_pjt_content())
    create_file("#{project_name}/src/prompts/bird/03_revision.pjt", revision_pjt_content())
    create_file("#{project_name}/.gitignore", "release\n")

    IO.puts("Pidge app #{project_name} has been created\n\nOnce you change directory you can run your project with:\n\n  $ cd #{project_name} ; pidge go --session dove-blog --human-input \"a personal blog site for my pet dove\"\n\n")
  end

  defp create_directory(path) do
    File.mkdir_p!(path)
  end

  defp create_file(path, content) do
    File.write!(path, content)
  end

  defp main_pj_content do
    """
    Context.add_conversation(:bird)
    Context.add_conversation(:insight)

    ai_prompt(:bird, "bird/01_example", human_input: true)
    |> ai_pipethru(:insight, "insight/02_critique")
    |> ai_pipethru(:bird, "bird/03_revision", optional_human_input: true)
    """
  end

  defp example_pjt_content do
    """
    Hello, I would like to work on a {{ human_input }} project with you. Please give me a layout we could do to go about this in an effective way.
    """
  end

  defp critique_pjt_content do
    """
    In this conversation I need you to be an advisor on a new project, I am working on. This is my rough idea:

    {{ input }}

    Please give me your feedback, find the areas we may be missing. Specifically I need this project to be impactful, and make the most difference and add the most value. Identify the areas where my plan might break down, and ask me the hard questions.
    """
  end

  defp revision_pjt_content do
    """
    Ok, I like your plan, but please consider the following feedback:

    {{ input }}

    {% if human_input %}

      But my most important advice, is this. Please pay close attention:

      {{ human_input }}

    {% endif %}
    """
  end

end
