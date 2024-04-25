//// Create a gleaming trail of application logs. 

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
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
  Context(level_text, text_formatter, Info)
}

@external(erlang, "comet_ffi", "configure")
@external(javascript, "./logs.mjs", "set_config")
pub fn configure(ctx: Context(t)) -> Nil

pub fn with_level_text(ctx: Context(t), func: fn(Level) -> String) -> Context(t) {
  Context(..ctx, level_text: func)
}

pub fn with_formatter(ctx: Context(t), formatter: Formatter(t)) -> Context(t) {
  Context(..ctx, formatter: formatter)
}

pub fn with_level(ctx: Context(t), level: Level) -> Context(t) {
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

pub type Entry(t) {
  Entry(level: Level, message: String, metadata: Metadata(t))
}

// Formatting ---------------------------------------------------------------------------

@target(erlang)
type Formatter(t) =
  fn(Context(t), Entry(t)) -> List(String)

@target(javascript)
type Formatter(t) =
  fn(Context(t), Entry(t)) -> String

@target(erlang)
pub fn text_formatter(ctx: Context(t), entry: Entry(t)) -> List(String) {
  let Entry(level, msg, md) = entry
  [
    "level: ",
    ctx.level_text(level),
    " | ",
    string.inspect(md),
    " | ",
    msg,
    "\n",
  ]
}

@target(javascript)
pub fn text_formatter(ctx: Context(t), entry: Entry(t)) -> String {
  let Entry(level, msg, md) = entry
  ["level:", ctx.level_text(level), "|", string.inspect(md), "|", msg]
  |> string.join(" ")
}

@target(erlang)
pub fn format(
  log: Dict(Atom, Dynamic),
  config: List(Dict(Atom, Context(t))),
) -> List(String) {
  let ctx = extract_context_from_config(config)
  ctx.formatter(ctx, extract_entry_from_erlang_log_event(log))
}

@target(erlang)
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

// Log APIs ---------------------------------------------------------------------------

pub fn log() -> Metadata(t) {
  new_metadata()
}

@target(erlang)
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  debug_erlang(prepare_metadata_for_erlang(md), msg)
}

@target(erlang)
@external(erlang, "comet_ffi", "debug")
fn debug_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  debug_javascript(Debug, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "debug")
fn debug_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
pub fn info(md: Metadata(t), msg: String) -> Nil {
  info_erlang(prepare_metadata_for_erlang(md), msg)
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
  warning_erlang(prepare_metadata_for_erlang(md), msg)
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
  error_erlang(prepare_metadata_for_erlang(md), msg)
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

@target(erlang)
const comet_metadata_stash_key = "comet metadata stash key"

// TODO: performance optiziation in erlang would be to build the Dict(Atom, AttribeSet)
// while each attribute is added and store it in the Metadata. This would prevent rebuilding
// of metadata entries and atom conversions for log builders that are cached with
// default attributes in them
@target(erlang)
fn prepare_metadata_for_erlang(md: Metadata(t)) -> Dict(Atom, AttributeSet(t)) {
  let key = key_name(comet_metadata_stash_key)
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
