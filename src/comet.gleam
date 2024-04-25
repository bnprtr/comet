//// Create a gleaming trail of application logs. 

import birl
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Level {
  Debug
  Info
  Warning
  Err
  Panic
}

pub fn level_text(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warning -> "warn"
    Err -> "error"
    Panic -> "panic"
  }
}

pub fn level_priority(level: Level) -> Int {
  case level {
    Debug -> 1
    Info -> 2
    Warning -> 3
    Err -> 4
    Panic -> 5
  }
}

// Context ---------------------------------------------------------------------------

pub opaque type Context {
  Context(
    level_text: fn(Level) -> String,
    formatter: Formatter,
    filters: Filters,
    min_level: Level,
    metadata: Metadata,
    default_handler: Option(Handler),
    handlers: List(Handler),
  )
}

pub fn new() -> Context {
  Context(
    level_text,
    text_formatter,
    [],
    Info,
    new_metadata(),
    default_handler(),
    [],
  )
}

@external(erlang, "comet_ffi", "configure")
@external(javascript, "./logs.mjs", "set_config")
pub fn configure(ctx: Context) -> Nil

pub fn set_level_text(ctx: Context, func: fn(Level) -> String) -> Context {
  Context(..ctx, level_text: func)
}

pub fn set_formatter(ctx: Context, formatter: Formatter) -> Context {
  Context(..ctx, formatter: formatter)
}

pub fn level(ctx: Context, level: Level) -> Context {
  Context(..ctx, min_level: level)
}

pub fn with_attribute(ctx: Context, attr: Attribute) -> Context {
  Context(..ctx, metadata: attribute(ctx.metadata, attr))
}

@target(erlang)
pub type Handler {
  Handler(
    module: Atom,
    min_level: Level,
    formatter_module: Atom,
    filters: List(ErlangFilter),
    metadata: Metadata,
  )
}

@target(erlang)
fn default_handler() -> Option(Handler) {
  None
}

@target(javascript)
pub type Handler {
  Handler(
    name: String,
    min_level: Level,
    formatter: Formatter,
    filters: Filters,
    metadata: Metadata,
  )
}

@target(javascript)
fn default_handler() {
  None
}

@target(erlang)
pub type HandlerFn =
  fn(Dict(Atom, Dynamic)) -> Nil

@target(javascript)
pub type HandlerFn =
  fn(Entry) -> Nil

@target(javascript)
pub fn add_handler(ctx: Context, handler: Handler) -> Context {
  Context(..ctx, handlers: list.append(ctx.handlers, [handler]))
}

// Metadata ---------------------------------------------------------------------------

pub type Metadata =
  List(Attribute)

fn new_metadata() -> Metadata {
  []
}

pub type Attribute {
  STR(name: String, value: String)
  INT(name: String, value: Int)
  FLOAT(name: String, value: Float)
  BOOL(name: String, value: Bool)
}

// pub fn json_formatter(
//   level: Level,
//   msg: String,
//   attributes: List(Attribute),
// ) -> String {
//   list.map(
//     list.concat([
//       [String("level", get_level_text(level))],
//       attributes,
//       [String("msg", msg)],
//     ]),
//     attribute_to_json,
//   )
//   |> json.object
//   |> json.to_string
// }

fn attribute_to_json(attr: Attribute) -> #(String, json.Json) {
  case attr {
    STR(key, value) -> #(key, json.string(value))
    INT(key, value) -> #(key, json.int(value))
    FLOAT(key, value) -> #(key, json.float(value))
    BOOL(key, value) -> #(key, json.bool(value))
  }
}

fn package_metadata_for_erlang(md: Metadata) -> Dict(Atom, Attribute) {
  add_atom_attributes_to_dict(md, dict.new())
}

fn add_atom_attributes_to_dict(
  md: Metadata,
  data: Dict(Atom, Attribute),
) -> Dict(Atom, Attribute) {
  case md {
    [] -> data
    [first, ..rest] ->
      add_atom_attributes_to_dict(
        rest,
        dict.insert(data, key_name(first.name), first),
      )
  }
}

fn attribute_decoder(
  value: Dynamic,
) -> Result(Attribute, List(dynamic.DecodeError)) {
  case dynamic.classify(value) {
    "STR" -> Ok(unsafe_dynamic_to_attribute(value))
    "BOOL" -> Ok(unsafe_dynamic_to_attribute(value))
    "INT" -> Ok(unsafe_dynamic_to_attribute(value))
    "FLOAT" -> Ok(unsafe_dynamic_to_attribute(value))
    _ -> Error([])
  }
}

fn unsafe_dynamic_to_attribute(value: Dynamic) -> Attribute {
  dynamic.unsafe_coerce(value)
}

pub fn attribute(md: Metadata, attribute: Attribute) -> Metadata {
  list.prepend(md, attribute)
}

// Filters ---------------------------------------------------------------------------
// TODO: 
//    - fix erlang filters..or try to understand them better and reimplement the filtering system 
//    - implement javascript s

pub type Entry {
  Entry(level: Level, message: String, metadata: Metadata)
}

type Filter =
  fn(Entry) -> Option(Entry)

pub type ErlangFilter

@target(erlang)
type Filters =
  List(ErlangFilter)

@target(javascript)
type Filters =
  List(Filter)

@target(javascript)
pub fn add_allow_metadata_filter(
  ctx: Context,
  name: String,
  filter: Filter,
) -> Context {
  Context(..ctx, filters: list.append(ctx.filters, [#(name, filter)]))
}

@external(erlang, "comet_ffi", "allow_metadata_filter")
fn add_allow_metadata_filter_erlang(keys: List(Atom)) -> ErlangFilter

@external(erlang, "comet_ffi", "deny_metadata_filter")
fn add_deny_metadata_filter_erlang(keys: List(Atom)) -> ErlangFilter

@target(erlang)
pub fn add_allow_metadata_filter(ctx: Context, keys: List(String)) -> Context {
  Context(
    ..ctx,
    filters: list.append(ctx.filters, [
      add_allow_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

@target(erlang)
pub fn add_allow_metadata_filter_to_handler(
  handler: Handler,
  keys: List(String),
) -> Handler {
  Handler(
    ..handler,
    filters: list.append(handler.filters, [
      add_allow_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

@target(erlang)
pub fn add_deny_metadata_filter(ctx: Context, keys: List(String)) -> Context {
  Context(
    ..ctx,
    filters: list.append(ctx.filters, [
      add_deny_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

@target(erlang)
pub fn add_deny_metadata_filter_to_handler(
  handler: Handler,
  keys: List(String),
) -> Handler {
  Handler(
    ..handler,
    filters: list.append(handler.filters, [
      add_deny_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

// Formatting ---------------------------------------------------------------------------

@target(erlang)
type Formatter =
  fn(Entry) -> List(String)

@target(javascript)
type Formatter =
  fn(Entry) -> #(String, List(Dynamic))

@target(erlang)
pub fn text_formatter(entry: Entry) -> List(String) {
  let Entry(level, msg, md) = entry
  ["level: ", level_text(level), " | ", msg, " | ", string.inspect(md)]
}

@target(erlang)
pub fn json_formatter(entry: Entry) -> List(String) {
  todo
  // let Entry(level, msg, md) = entry
  // md
  // |> dict.insert(key_name("level"), level_text(level))
  // |> dict.insert(key_name("msg"), msg)
  // let fields = [#("level", json.string(level_text(level)), #("msg", json.string(msg)))]
  // |> list.append()
  // json.object()
}

@target(javascript)
pub fn text_formatter(entry: Entry) -> #(String, List(Dynamic)) {
  let Entry(level, msg, md) = entry
  let msg =
    ["level:", level_text(level), "|", msg]
    |> string.join(" ")
  #(msg, [dynamic.from(md)])
}

@target(erlang)
type LogEvent {
  Dict(Atom, Attribute)
  String
}

@target(erlang)
pub fn format(
  log: Dict(Atom, Dynamic),
  config: List(#(Atom, Context)),
) -> List(String) {
  let ctx = extract_context_from_config(config)
  ctx.formatter(extract_entry_from_erlang_log_event(log))
}

fn extract_context_from_config(config: List(#(Atom, Context))) -> Context {
  case list.first(config) {
    Ok(#(_, v)) -> v
    _ -> new()
  }
}

@target(erlang)
fn extract_entry_from_erlang_log_event(log: Dict(Atom, Dynamic)) -> Entry {
  let level: Level = extract_level_from_erlang_log(log)
  let msg: String = extract_msg_from_erlang_log(log)
  let metadata: Metadata = extract_metadata_from_erlang_log(log)
  Entry(level, msg, metadata)
}

@target(erlang)
fn extract_metadata_from_erlang_log(log: Dict(Atom, Dynamic)) -> Metadata {
  case dict.get(log, key_name("meta")) {
    Ok(value) ->
      case dynamic.dict(atom.from_dynamic, dynamic.dynamic)(value) {
        Ok(md) -> list.filter_map(dict.values(md), attribute_decoder)
        _ -> new_metadata()
      }
    _ -> new_metadata()
  }
}

@target(erlang)
fn extract_level_from_erlang_log(log: Dict(Atom, Dynamic)) -> Level {
  case dict.get(log, key_name("level")) {
    Ok(value) -> decode_level(value)
    _ -> Err
  }
}

@target(erlang)
fn decode_level(value: Dynamic) -> Level {
  case atom.from_dynamic(value) {
    Ok(level) -> {
      case atom.to_string(level) {
        "debug" -> Debug
        _ -> Err
      }
    }
    _ -> Err
  }
}

@target(erlang)
fn extract_msg_from_erlang_log(log: Dict(Atom, Dynamic)) -> String {
  case dict.get(log, key_name("msg")) {
    Ok(value) ->
      case
        result.try(
          dynamic.tuple2(atom.from_dynamic, dynamic.string)(value),
          fn(a: #(Atom, String)) { Ok(a.1) },
        )
      {
        Ok(msg) -> msg
        _ -> ""
      }
    _ -> ""
  }
}

// @target(erlang)
// fn decode_level(value: Dynamic) -> Level {
//   case atom.from_dynamic(value) {
//     Ok(level) -> {
//       case atom.to_string(level) {
//         "debug" -> Debug
//         _ -> Err
//       }
//     }
//     _ -> Err
//   }
// }

@target(erlang)
fn key_name(name: String) -> Atom {
  case atom.from_string(name) {
    Ok(a) -> a
    _ -> atom.create_from_string(name)
  }
}

@target(javascript)
fn key_name(name: String) -> String {
  name
}

// Log APIs ---------------------------------------------------------------------------

pub fn log() -> Metadata {
  new_metadata()
}

@external(erlang, "comet_ffi", "debug")
@external(javascript, "./logs.mjs", "debug")
pub fn debug(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "info")
@external(javascript, "./logs.mjs", "info")
pub fn info(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "warning")
@external(javascript, "./logs.mjs", "warning")
pub fn warning(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "error")
@external(javascript, "./logs.mjs", "error")
pub fn error(md: Metadata, msg: String) -> Nil
