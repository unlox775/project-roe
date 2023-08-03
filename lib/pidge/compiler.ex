#!/usr/bin/env elixir

File.mkdir_p!("release")

{:ok, code} = File.read("main.pj")
{:ok, ast} = Code.string_to_quoted(code)

Code.require_file("ast_compiler.ex")
pidge_ast = AstCompiler.parse_ast(ast)
AstCompiler.validate_ast(pidge_ast)
prompt_files = AstCompiler.compile_prompts(pidge_ast)

# Copy all the prompt files under release/prompts/
prompt_files |> Enum.each(fn filename ->
  new_file_path = "release/#{filename}"
  dirname = Path.dirname(new_file_path)
  File.mkdir_p!(dirname)
  File.write!(new_file_path, File.read!(filename))
end)

File.write!("release/main.pjc", inspect(pidge_ast))
