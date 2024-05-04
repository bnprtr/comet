import comet.{type Context, Entry, new}
import comet/level.{type Level, Debug, Error as Err, Info, Warning}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{
  type Atom, create_from_string as create_atom_from_string,
  from_dynamic as atom_from_dynamic, from_string as atom_from_string,
} as glatom
import gleam/erlang/charlist.{type Charlist}
import gleam/option.{None, Some}
import gleam/result

const comet_metadata_stash_key = "comet metadata stash key"

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
  let handler = case comet.get_handler(ctx) {
    Some(handler) -> handler
    None -> panic
  }
  let entry = extract_entry_from_erlang_log_event(event)
  let formatted = case comet.get_formatter(ctx) {
    None ->
      logger_format_erlang(event, config)
      |> charlist.to_string
    Some(formatter) -> formatter(ctx, entry)
  }
  handler(formatted)
}

@target(erlang)
@external(erlang, "logger_formatter", "format")
fn logger_format_erlang(log event: LogEvent, config map: Config(t)) -> Charlist

@target(erlang)
/// Format is used for formatting log entries into strings. by the default erlang logger.
pub fn format(
  log: Dict(Atom, Dynamic),
  config: Dict(Atom, Context(t)),
) -> Charlist {
  let ctx = extract_context_from_config(config)
  let assert Some(formatter) = comet.get_formatter(ctx)
  charlist.from_string(formatter(ctx, extract_entry_from_erlang_log_event(log)))
}

@target(erlang)
fn extract_context_from_config(config: Dict(Atom, Context(t))) -> Context(t) {
  case dict.get(config, atom("config")) {
    Ok(ctx) -> ctx
    _ -> new()
  }
}

@target(erlang)
fn extract_entry_from_erlang_log_event(
  log: Dict(Atom, Dynamic),
) -> comet.Entry(t) {
  let level: Level = extract_level_from_erlang_log(log)
  let msg: String = extract_msg_from_erlang_log(log)
  let metadata = extract_metadata_from_erlang_log(log)
  Entry(level, msg, metadata)
}

// this is some nasty stuff to extract the attributes from the erlang logger data.
// maybe there is a better way to do this.
@target(erlang)
fn extract_metadata_from_erlang_log(log: Dict(Atom, Dynamic)) -> List(t) {
  case dict.get(log, atom("meta")) {
    Ok(value) ->
      case dynamic.dict(atom_from_dynamic, dynamic.dynamic)(value) {
        Ok(md) ->
          case dict.get(md, atom(comet_metadata_stash_key)) {
            Ok(data) ->
              case dynamic.unsafe_coerce(data) {
                comet.CometAttributeList(data) -> data
                _ -> []
              }
            _ -> []
          }

        _ -> []
      }
    _ -> []
  }
}

@target(erlang)
fn extract_level_from_erlang_log(log: Dict(Atom, Dynamic)) -> level.Level {
  case dict.get(log, atom("level")) {
    Ok(value) -> decode_level(value)
    _ -> Err
  }
}

@target(erlang)
fn decode_level(value: Dynamic) -> Level {
  case glatom.from_dynamic(value) {
    Ok(level) -> {
      case glatom.to_string(level) {
        "debug" -> Debug
        "info" -> Info
        "warning" -> Warning
        "error" -> Err
        _ -> Err
      }
    }
    _ -> Err
  }
}

@target(erlang)
fn extract_msg_from_erlang_log(log: Dict(Atom, Dynamic)) -> String {
  case dict.get(log, atom("msg")) {
    Ok(value) ->
      case
        result.try(
          dynamic.tuple2(glatom.from_dynamic, dynamic.string)(value),
          fn(a: #(Atom, String)) { Ok(a.1) },
        )
      {
        Ok(msg) -> msg
        _ -> ""
      }
    _ -> ""
  }
}
