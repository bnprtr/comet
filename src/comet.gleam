//// Create a gleaming trail of application logs. 

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{
  type Atom, create_from_string as create_atom_from_string,
  from_dynamic as atom_from_dynamic, from_string as atom_from_string,
  to_string as atom_to_string,
} as _
import gleam/erlang/charlist.{type Charlist, to_string as charlist_to_string}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import level.{type Level, Debug, Error as Err, Info, Warning, level_text}

pub type AttributeSet(t) {

  // attributes added to the erlang metadata directly
  Attribute(t)

  // The erlang logger sends the metadata to formatters as a Dict(Atom, Dynamic)
  // which puts way too much stress on the client developer to properly decode their
  // attributes in a propably unsafe way. Instead, we insert a metadata entry into the
  // dictionary so that the Erlang logger can properly filter on the metadata but
  // we instead stick all of the metadata into a list of a known atom. Since the
  // list is of type T when we unsafe_coerce, the client developer can simply
  // use pattern matching to handle the metadata easily. CometAttributeList is
  // the internal metadata entry used for storing all attributes.
  CometAttributeList(List(t))
}

pub const comet_metadata_stash_key = "comet metadata stash key"

pub type Formatter(t) =
  fn(Context(t), Entry(t)) -> String

pub type Context(t) {
  Context(
    level_text: fn(Level) -> String,
    formatter: Option(Formatter(t)),
    min_level: Level,
    handler: Option(Handler),
  )
}

pub fn configure(ctx: Context(t)) -> Context(t) {
  initialize_context(ctx)
}

pub fn new() -> Context(t) {
  Context(level_text, None, Info, None)
}

pub type Metadata(t) =
  List(t)

pub type Entry(t) {
  Entry(level: Level, message: String, metadata: Metadata(t))
}

pub type Handler =
  fn(String) -> Nil

pub fn extract_context_from_config(config: Dict(Atom, Context(t))) -> Context(t) {
  case dict.get(config, atom("config")) {
    Ok(ctx) -> ctx
    _ -> new()
  }
}

pub fn text_formatter(ctx: Context(t), entry: Entry(t)) -> String {
  let Entry(level, msg, md) = entry
  ["level:", ctx.level_text(level), "|", string.inspect(md), "|", msg]
  |> string.join(" ")
}

@target(erlang)
pub fn extract_entry_from_erlang_log_event(log: Dict(Atom, Dynamic)) -> Entry(t) {
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
                CometAttributeList(data) -> data
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
fn extract_level_from_erlang_log(log: Dict(Atom, Dynamic)) -> Level {
  case dict.get(log, atom("level")) {
    Ok(value) -> decode_level(value)
    _ -> Err
  }
}

@target(erlang)
fn decode_level(value: Dynamic) -> Level {
  case atom_from_dynamic(value) {
    Ok(level) -> {
      case atom_to_string(level) {
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
          dynamic.tuple2(atom_from_dynamic, dynamic.string)(value),
          fn(a: #(Atom, String)) { Ok(a.1) },
        )
      {
        Ok(msg) -> msg
        _ -> ""
      }
    _ -> ""
  }
}

@target(erlang)
fn initialize_context(log ctx: Context(t)) -> Context(t) {
  prepare_erlang_handler_config(ctx)
  |> update_primary_config_erlang

  maybe_add_formatter_to_context(ctx)
}

@target(erlang)
fn prepare_erlang_handler_config(ctx: Context(t)) -> Dict(Atom, Dynamic) {
  dict.new()
  |> dict.insert(atom("level"), dynamic.from(ctx.min_level))
  |> dict.insert(atom("filter_default"), dynamic.from(atom("log")))
  |> dict.insert(atom("filters"), dynamic.from([]))
  |> dict.insert(atom("metadata"), dynamic.from(dict.new()))
}

// #(Formatter, LoggerFormatter(dict.from_list([#(SingleLine, False), #(LegacyHeader, True)])))])])
@target(erlang)
fn maybe_add_formatter_to_context(ctx: Context(t)) -> Context(t) {
  case ctx.formatter {
    None -> {
      let formatter_config =
        dict.new()
        |> dict.insert(atom("formatter"), #(
          atom("logger_formatter"),
          dict.new()
            |> dict.insert(
            atom("config"),
            dynamic.from(
              dict.new()
              |> dict.insert(atom("single_line"), False)
              |> dict.insert(atom("legacy_header"), True),
            ),
          ),
        ))

      update_handler_config_erlang(atom("default"), formatter_config)
      ctx
    }
    Some(formatter) -> {
      let formatter_config =
        dict.new()
        |> dict.insert(atom("formatter"), #(
          atom("comet"),
          dict.new()
            |> dict.insert(atom("config"), ctx),
        ))

      update_handler_config_context_erlang(atom("default"), formatter_config)
      ctx
    }
  }
}

@target(javascript)
fn initialize_context(log ctx: Context(t)) -> Context(t) {
  set_config_javascript(ctx)
  ctx
}

@external(javascript, "./logs.mjs", "set_config")
fn set_config_javascript(config: Dict(Atom, Dynamic)) -> Nil

@target(erlang)
pub fn atom(name: String) -> Atom {
  case atom_from_string(name) {
    Ok(a) -> a
    _ -> create_atom_from_string(name)
  }
}

@external(erlang, "logger", "update_handler_config")
fn update_handler_config_context_erlang(
  handler id: Atom,
  config config: Dict(Atom, #(Atom, Dict(Atom, Context(t)))),
) -> Nil

@external(erlang, "logger", "update_handler_config")
fn update_handler_config_erlang(
  handler id: Atom,
  config config: Dict(Atom, #(Atom, Dict(Atom, Dynamic))),
) -> Nil

@external(erlang, "logger", "set_handler_config")
fn set_handler_config_erlang(
  handler id: Atom,
  module name: Atom,
  config map: #(Atom, Dynamic),
) -> Nil

//  logger:update_primary_config(#{
//    level => MinLevel,
//    filter_default => log,
//    filters => [],
//    metadata => #{}
//  }),
@external(erlang, "logger", "update_primary_config")
fn update_primary_config_erlang(config map: Dict(Atom, Dynamic)) -> Nil

// Context ---------------------------------------------------------------------------

pub fn with_level_text(ctx: Context(t), func: fn(Level) -> String) -> Context(t) {
  Context(..ctx, level_text: func)
}

pub fn with_formatter(ctx: Context(t), formatter: Formatter(t)) -> Context(t) {
  Context(..ctx, formatter: Some(formatter))
}

pub fn with_level(ctx: Context(t), level: Level) -> Context(t) {
  Context(..ctx, min_level: level)
}

// Handlers ---------------------------------------------------------------------------

@target(erlang)
pub fn add_handler(ctx: Context(t), name: String, handler: Handler) -> Nil {
  let ctx = Context(..ctx, handler: Some(handler))
  let config =
    prepare_erlang_handler_config(ctx)
    |> dict.insert(
      atom("formatter"),
      dynamic.from(#(
        atom("comet"),
        dict.new()
          |> dict.insert(atom("config"), ctx),
      )),
    )
    |> dict.insert(atom("id"), dynamic.from(atom(name)))
    |> dict.insert(atom("module"), dynamic.from(atom("comet_handler")))
    |> dict.insert(atom("config"), dynamic.from(ctx))
  add_handler_erlang(atom(name), atom("comet_handler"), config)
}

// logger:add_handler(Name, Module, #{
//     level => MinLevel,
//     filter_default => log,
//     config => Handler,
//     filters => [],
//     formatter => {comet, [#{config => Handler}]},
//     metadata => #{}
// }),
@external(erlang, "logger", "add_handler")
fn add_handler_erlang(
  name: Atom,
  module: Atom,
  config: Dict(Atom, Dynamic),
) -> Nil

// Metadata ---------------------------------------------------------------------------

fn new_metadata() -> Metadata(t) {
  []
}

pub fn attribute(md: Metadata(t), attribute: t) -> Metadata(t) {
  list.prepend(md, attribute)
}

pub fn attributes(md: Metadata(t), attributes: List(t)) -> Metadata(t) {
  list.append(md, attributes)
}

// Formatting ---------------------------------------------------------------------------

@target(erlang)
pub fn format(
  log: Dict(Atom, Dynamic),
  config: Dict(Atom, Context(t)),
) -> Charlist {
  let ctx = extract_context_from_config(config)
  let assert Some(formatter) = ctx.formatter
  charlist.from_string(formatter(ctx, extract_entry_from_erlang_log_event(log)))
}

// Log APIs ---------------------------------------------------------------------------

pub fn log() -> Metadata(t) {
  new_metadata()
}

@target(erlang)
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Debug, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "logger", "log")
fn log_erlang(level: Level, msg: String, md: Dict(Atom, AttributeSet(t))) -> Nil

@target(javascript)
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  debug_javascript(Debug, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "debug")
fn debug_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn info(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Info, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "info")
fn info_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
pub fn info(md: Metadata(t), msg: String) -> Nil {
  info_javascript(Info, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "info")
fn info_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn warning(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Warning, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "warning")
fn warning_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
pub fn warning(md: Metadata(t), msg: String) -> Nil {
  warning_javascript(Warning, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "warning")
fn warning_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn error(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Err, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "error")
fn error_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
pub fn error(md: Metadata(t), msg: String) -> Nil {
  error_javascript(Err, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "error")
fn error_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

// Erlang Interface -------------------------------------------------------------------

// TODO: performance optiziation in erlang would be to build the Dict(Atom, AttribeSet)
// while each attribute is added and store it in the Metadata. This would prevent rebuilding
// of metadata entries and atom conversions for log builders that are cached with
// default attributes in them
@target(erlang)
fn prepare_metadata_for_erlang(md: Metadata(t)) -> Dict(Atom, AttributeSet(t)) {
  let key = atom(comet_metadata_stash_key)
  md
  |> convert_metadata_to_atom_dict(dict.new())
  |> dict.insert(key, CometAttributeList(md))
}

@target(erlang)
fn convert_metadata_to_atom_dict(
  md: Metadata(t),
  data: Dict(Atom, AttributeSet(t)),
) -> Dict(Atom, AttributeSet(t)) {
  case md {
    [] -> data
    [first, ..rest] ->
      convert_metadata_to_atom_dict(
        rest,
        dict.insert(data, attribute_atom(first), Attribute(first)),
      )
  }
}

@target(erlang)
@external(erlang, "comet_ffi", "get_attribute_atom")
fn attribute_atom(attribute: t) -> Atom
