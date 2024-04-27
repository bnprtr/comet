import comet.{type Context, Context, extract_entry_from_erlang_log_event, new}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{
  type Atom, create_from_string as create_atom_from_string,
  from_string as atom_from_string,
} as _
import gleam/erlang/charlist.{type Charlist}
import gleam/io
import gleam/option.{None, Some}
import gleam/string

@target(erlang)
pub fn atom(name: String) -> Atom {
  case atom_from_string(name) {
    Ok(a) -> a
    _ -> create_atom_from_string(name)
  }
}

type LogEvent =
  Dict(Atom, Dynamic)

type Config(t) =
  Dict(Atom, Context(t))

@target(erlang)
pub fn log(event: LogEvent, config: Config(t)) -> Nil {
  let ctx: Context(t) = case dict.get(config, atom("config")) {
    Ok(ctx) -> ctx
    _ -> new()
  }
  let handler = case ctx.handler {
    Some(handler) -> handler
    None -> panic
  }
  let entry = extract_entry_from_erlang_log_event(event)
  let formatted = case ctx.formatter {
    None ->
      logger_format_erlang(event, config)
      |> charlist.to_string
    Some(formatter) -> formatter(ctx, entry)
  }
  handler(formatted)
}

@external(erlang, "logger_formatter", "format")
fn logger_format_erlang(log event: LogEvent, config map: Config(t)) -> Charlist
