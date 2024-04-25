//// Create a gleaming trail of application logs. 

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/io
import gleam/list
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

pub opaque type Context(t) {
  Context(
    level_text: fn(Level) -> String,
    formatter: Formatter(t),
    filters: Filters,
    min_level: Level,
  )
}

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

pub fn new() -> Context(t) {
  Context(level_text, text_formatter, [], Info)
}

@external(erlang, "comet_ffi", "configure")
@external(javascript, "./logs.mjs", "set_config")
pub fn configure(ctx: Context(t)) -> Nil

pub fn set_level_text(ctx: Context(t), func: fn(Level) -> String) -> Context(t) {
  Context(..ctx, level_text: func)
}

pub fn set_formatter(ctx: Context(t), formatter: Formatter(t)) -> Context(t) {
  Context(..ctx, formatter: formatter)
}

pub fn level(ctx: Context(t), level: Level) -> Context(t) {
  Context(..ctx, min_level: level)
}

// Metadata ---------------------------------------------------------------------------

pub type Metadata(t) =
  List(t)

fn new_metadata() -> Metadata(t) {
  []
}

pub fn attribute(md: Metadata(t), attribute: t) -> Metadata(t) {
  list.prepend(md, attribute)
}

// Filters ---------------------------------------------------------------------------
// TODO: 
//    - fix erlang filters..or try to understand them better and reimplement the filtering system 
//    - implement javascript

pub type Entry(t) {
  Entry(level: Level, message: String, metadata: Metadata(t))
}

type ErlangFilter

@target(erlang)
type Filters =
  List(ErlangFilter)

@target(javascript)
type Filters =
  List(Filter)

@target(javascript)
pub fn add_allow_metadata_filter(
  ctx: Context(t),
  name: String,
  filter: Filter,
) -> Context(t) {
  Context(..ctx, filters: list.append(ctx.filters, [#(name, filter)]))
}

@external(erlang, "comet_ffi", "allow_metadata_filter")
fn add_allow_metadata_filter_erlang(keys: List(Atom)) -> ErlangFilter

@external(erlang, "comet_ffi", "deny_metadata_filter")
fn add_deny_metadata_filter_erlang(keys: List(Atom)) -> ErlangFilter

@target(erlang)
pub fn add_allow_metadata_filter(
  ctx: Context(t),
  keys: List(String),
) -> Context(t) {
  Context(
    ..ctx,
    filters: list.append(ctx.filters, [
      add_allow_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

@target(erlang)
pub fn add_deny_metadata_filter(
  ctx: Context(t),
  keys: List(String),
) -> Context(t) {
  Context(
    ..ctx,
    filters: list.append(ctx.filters, [
      add_deny_metadata_filter_erlang(list.map(keys, fn(k) { key_name(k) })),
    ]),
  )
}

// Formatting ---------------------------------------------------------------------------

type Formatter(t) =
  fn(Entry(t)) -> List(String)

@target(erlang)
pub fn text_formatter(entry: Entry(t)) -> List(String) {
  let Entry(level, msg, md) = entry
  ["level: ", level_text(level), " | ", string.inspect(md), " | ", msg, "\n"]
}

@target(javascript)
pub fn text_formatter(entry: Entry(t)) -> #(String, List(Dynamic)) {
  let Entry(level, msg, md) = entry
  let msg =
    ["level:", level_text(level), "|", msg]
    |> string.join(" ")
  #(msg, [dynamic.from(md)])
}

@target(erlang)
pub fn format(
  log: Dict(Atom, Dynamic),
  config: List(Dict(Atom, Context(t))),
) -> List(String) {
  let ctx = extract_context_from_config(config)
  ctx.formatter(extract_entry_from_erlang_log_event(log))
}

fn extract_context_from_config(
  config: List(Dict(Atom, Context(t))),
) -> Context(t) {
  case list.first(config) {
    Ok(d) ->
      case dict.get(d, key_name("config")) {
        Ok(ctx) -> ctx
        _ -> new()
      }
    _ -> new()
  }
}

@target(erlang)
fn extract_entry_from_erlang_log_event(log: Dict(Atom, Dynamic)) -> Entry(t) {
  let level: Level = extract_level_from_erlang_log(log)
  let msg: String = extract_msg_from_erlang_log(log)
  let metadata = extract_metadata_from_erlang_log(log)
  Entry(level, msg, metadata)
}

// this is some nasty stuff to extract the attributes from the erlang logger data.
// maybe there is a better way to do this.
@target(erlang)
fn extract_metadata_from_erlang_log(log: Dict(Atom, Dynamic)) -> List(t) {
  case dict.get(log, key_name("meta")) {
    Ok(value) ->
      case dynamic.dict(atom.from_dynamic, dynamic.dynamic)(value) {
        Ok(md) ->
          case dict.get(md, key_name(comet_metadata_stash_key)) {
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

pub fn log() -> Metadata(t) {
  new_metadata()
}

@target(erlang)
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  debug_erlang(prepare_metadata_for_erlang(md), msg)
}

@external(erlang, "comet_ffi", "debug")
fn debug_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
@external(javascript, "./logs.mjs", "debug")
pub fn debug(md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn info(md: Metadata(t), msg: String) -> Nil {
  info_erlang(prepare_metadata_for_erlang(md), msg)
}

@external(erlang, "comet_ffi", "info")
fn info_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
@external(javascript, "./logs.mjs", "info")
pub fn info(md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn warning(md: Metadata(t), msg: String) -> Nil {
  warning_erlang(prepare_metadata_for_erlang(md), msg)
}

@external(erlang, "comet_ffi", "warning")
fn warning_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
@external(javascript, "./logs.mjs", "warning")
pub fn warning(md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn error(md: Metadata(t), msg: String) -> Nil {
  error_erlang(prepare_metadata_for_erlang(md), msg)
}

@external(erlang, "comet_ffi", "error")
fn error_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
@external(javascript, "./logs.mjs", "error")
pub fn error(md: Metadata(t), msg: String) -> Nil

// Erlang Interface -------------------------------------------------------------------

const comet_metadata_stash_key = "comet metadata stash key"

// TODO: performance optiziation in erlang would be to build the Dict(Atom, AttribeSet)
// while each attribute is added and store it in the Metadata. This would prevent rebuilding
// of metadata entries and atom conversions for log builders that are cached with
// default attributes in them
fn prepare_metadata_for_erlang(md: Metadata(t)) -> Dict(Atom, AttributeSet(t)) {
  let key = key_name(comet_metadata_stash_key)
  md
  |> convert_metadata_to_atom_dict(dict.new())
  |> dict.insert(key, CometAttributeList(md))
}

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

@external(erlang, "comet_ffi", "get_attribute_atom")
fn attribute_atom(attribute: t) -> Atom
