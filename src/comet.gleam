//// Create a gleaming trail of application logs. 

import birl
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom as glatom
import gleam/erlang/charlist
import gleam/io
import gleam/javascript/map
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/string_builder
import gleam_community/ansi
import level.{type Level, Debug, Error as Err, Info, Warning, level_text}

@internal
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

const comet_metadata_stash_key = "comet metadata stash key"

/// Formatter is called by the logger to format the log entry into a string before it is sent to the
/// log handler. The formatter is passed the context and the log entry and should return a string.
/// The formatter is optional, if one is not provided than the default formatter is used.
pub type Formatter(t) =
  fn(Context(t), Entry(t)) -> String

/// Context contains logging settings.
@internal
pub opaque type Context(t) {
  Context(
    level_text: LevelTextFn,
    formatter: Option(Formatter(t)),
    min_level: Level,
    handler: Option(Handler),
    timestamp: Bool,
  )
}

/// configure is used to initialize the global logger settings. It should be called once at the
/// start of the application. You should not call it again after the logger has been initialized as
/// it will overwrite the global erlang and javascript logger settings.
pub fn configure(ctx: Context(t)) -> Context(t) {
  initialize_context(ctx)
}

/// new creates a new logger context with default settings.
/// The default settings are:
/// - level_text: debug, info, warn, error
/// - formatter: None (uses the backend default formatter)
/// - min_level: Info
pub fn new() -> Context(t) {
  Context(level_text, None, Info, None, True)
}

/// LevelTextFn can be provided to the log context to override the level names in logs
pub type LevelTextFn =
  fn(Level) -> String

/// Metadata is a list of attributes that can be attached to a log entry.
pub type Metadata(t) =
  List(t)

///  Entry is a log entry containing the log level, message, and metadata. This will be provided to
/// the log formatter to be converted into a string.
pub type Entry(t) {
  Entry(level: Level, message: String, metadata: Metadata(t))
}

/// Handlers are functions which receive a formatted string to be sent to the log destination.
/// The default handler emits logs to the console or standard_io in the case of the erlang backend.
/// Additional handlers can be added to the logger to send logs to other destinations, such as shipping
/// logs to a remote server or writing logs to a file.
pub type Handler =
  fn(String) -> Nil

fn label_color(str: String) -> String {
  str
  |> ansi.bold
  |> ansi.dim
  |> ansi.pink
}

fn value_color(str: String) -> String {
  str
  |> ansi.magenta
}

/// This is the standard text formatter for logs. It will format the log entry into a string
pub fn text_formatter(ctx: Context(t), entry: Entry(t)) -> String {
  let Entry(level, msg, md) = entry
  string_builder.new()
  |> string_builder.append(label_color("level"))
  |> string_builder.append("=")
  |> string_builder.append(ctx.level_text(level))
  |> maybe_add_timestamp_text(ctx)
  |> string_builder.append(label_color(" attributes"))
  |> string_builder.append("=")
  |> string_builder.append(value_color(string.inspect(md)))
  |> string_builder.append(label_color(" msg"))
  |> string_builder.append("=")
  |> string_builder.append(ansi.pink(msg))
  |> string_builder.to_string
}

fn maybe_add_timestamp_text(
  builder: string_builder.StringBuilder,
  ctx: Context(t),
) -> string_builder.StringBuilder {
  case ctx.timestamp {
    False -> builder
    True ->
      string_builder.append(builder, label_color(" time"))
      |> string_builder.append("=")
      |> string_builder.append(value_color(birl.to_iso8601(birl.now())))
  }
}

pub type AttributeJsonSerializer(t) =
  fn(t) -> #(String, json.Json)

pub fn json_formatter(serializer: AttributeJsonSerializer(t)) -> Formatter(t) {
  fn(ctx: Context(t), entry: Entry(t)) -> String {
    list.map(entry.metadata, serializer)
    |> list.prepend(#("level", json.string(ctx.level_text(entry.level))))
    |> maybe_add_timestamp_json(ctx)
    |> list.prepend(#("msg", json.string(entry.message)))
    |> json.object
    |> json.to_string
  }
}

fn maybe_add_timestamp_json(
  md: List(#(String, json.Json)),
  ctx: Context(t),
) -> List(#(String, json.Json)) {
  case ctx.timestamp {
    False -> md
    True ->
      list.prepend(md, #("time", json.string(birl.to_iso8601(birl.now()))))
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

@target(erlang)
fn maybe_add_formatter_to_context(ctx: Context(t)) -> Context(t) {
  case ctx.formatter {
    None -> {
      let formatter_config =
        dict.new()
        |> dict.insert(
          atom("formatter"),
          dynamic.from(#(
            atom("logger_formatter"),
            dict.new()
              |> dict.insert(atom("single_line"), dynamic.from(True))
              |> dict.insert(atom("legacy_header"), dynamic.from(False)),
          )),
        )
      update_handler_config_erlang(atom("default"), formatter_config)
      ctx
    }
    Some(formatter) -> {
      let formatter_config =
        dict.new()
        |> dict.insert(atom("formatter"), #(
          atom("comet_handler"),
          dict.new()
            |> dict.insert(
            atom("config"),
            // erlang logger doesn't add new lines by deafult so we need to wrap the formatter
            // to append new lines
            Context(
              ..ctx,
              formatter: Some(fn(ctx: Context(t), entry: Entry(t)) -> String {
                formatter(ctx, entry) <> "\n"
              }),
            ),
          ),
        ))
      update_handler_config_context_erlang(atom("default"), formatter_config)
      ctx
    }
  }
}

@target(javascript)
fn initialize_context(log ctx: Context(t)) -> Context(t) {
  let config =
    map.new()
    |> map.set("min_level", dynamic.from(level.level_priority(ctx.min_level)))
    |> map.set("formatter", dynamic.from(ctx.formatter))
    |> map.set("level_priority", dynamic.from(level.level_priority))
    |> map.set("timestamp", dynamic.from(ctx.timestamp))

  let config = case ctx.formatter {
    None -> config
    Some(formatter) -> {
      map.set(config, "formatter", dynamic.from(formatter))
    }
  }
  set_config_javascript(ctx, config)
  ctx
}

@external(javascript, "./logs.mjs", "setConfig")
fn set_config_javascript(
  config: Context(t),
  configuration: map.Map(string, Dynamic),
) -> Nil

@target(erlang)
fn atom(name: String) -> Atom {
  case glatom.from_string(name) {
    Ok(a) -> a
    _ -> glatom.create_from_string(name)
  }
}

// Context ---------------------------------------------------------------------------

/// Provide a function to override the log level names emitted in logs 
pub fn with_level_text(ctx: Context(t), func: fn(Level) -> String) -> Context(t) {
  Context(..ctx, level_text: func)
}

/// provide a custom formatter to format log entries
pub fn with_formatter(ctx: Context(t), formatter: Formatter(t)) -> Context(t) {
  Context(..ctx, formatter: Some(formatter))
}

/// set the log level for the logger
pub fn with_level(ctx: Context(t), level: Level) -> Context(t) {
  Context(..ctx, min_level: level)
}

/// togle timestamps
pub fn timestamp(ctx: Context(t), active: Bool) -> Context(t) {
  Context(..ctx, timestamp: active)
}

pub fn get_handler(ctx: Context(t)) -> Option(Handler) {
  ctx.handler
}

pub fn get_formatter(ctx: Context(t)) -> Option(Formatter(t)) {
  ctx.formatter
}

// Handlers ---------------------------------------------------------------------------

@target(erlang)
/// Set the context's handler to a custom Handler.
pub fn set_handler(ctx: Context(t), name: String, handler: Handler) -> Nil {
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

@target(erlang)
@external(erlang, "logger", "add_handler")
fn add_handler_erlang(
  name: Atom,
  module: Atom,
  config: Dict(Atom, Dynamic),
) -> Nil

@target(javascript)
/// Set the context's handler to a custom Handler.
pub fn add_handler(ctx: Context(t), name: String, handler: Handler) -> Nil {
  let config =
    map.new()
    |> map.set("min_level", dynamic.from(level.level_priority(ctx.min_level)))
    |> map.set("level_priority", dynamic.from(level.level_priority))
    |> map.set("handler", dynamic.from(handler))
    |> map.set("ctx", dynamic.from(ctx))
    |> map.set("timestamp", dynamic.from(ctx.timestamp))
  case ctx.formatter {
    None -> config
    Some(formatter) -> map.set(config, "formatter", dynamic.from(formatter))
  }
  |> add_handler_js(name)
}

@external(javascript, "./logs.mjs", "addHandler")
fn add_handler_js(config: map.Map(string, Dynamic), name: String) -> Nil

// Metadata ---------------------------------------------------------------------------

fn new_metadata() -> Metadata(t) {
  []
}

/// Add an attribute to the metadata.
pub fn attribute(md: Metadata(t), attribute: t) -> Metadata(t) {
  list.prepend(md, attribute)
}

/// Append a list of attributes to the metadata.
pub fn attributes(md: Metadata(t), attributes: List(t)) -> Metadata(t) {
  list.append(md, attributes)
}

// Log APIs ---------------------------------------------------------------------------

/// creates a new leg entry builder.
pub fn log() -> Metadata(t) {
  new_metadata()
}

@target(erlang)
/// log a message at the debug level
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Debug, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "logger", "log")
fn log_erlang(level: Level, msg: String, md: Dict(Atom, AttributeSet(t))) -> Nil

@target(javascript)
/// log a message at the debug level
pub fn debug(md: Metadata(t), msg: String) -> Nil {
  debug_javascript(Debug, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "debug")
fn debug_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
/// log a message at the info level
pub fn info(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Info, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "info")
fn info_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
/// log a message at the info level
pub fn info(md: Metadata(t), msg: String) -> Nil {
  info_javascript(Info, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "info")
fn info_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
/// log a message at the warning level
pub fn warning(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Warning, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "warning")
fn warning_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
/// log a message at the warning level
pub fn warning(md: Metadata(t), msg: String) -> Nil {
  warning_javascript(Warning, md, msg)
}

@target(javascript)
@external(javascript, "./logs.mjs", "warning")
fn warning_javascript(level: Level, md: Metadata(t), msg: String) -> Nil

@target(erlang)
/// log a message at the error level
pub fn error(md: Metadata(t), msg: String) -> Nil {
  log_erlang(Err, msg, prepare_metadata_for_erlang(md))
}

@target(erlang)
@external(erlang, "comet_ffi", "error")
fn error_erlang(md: Dict(Atom, AttributeSet(t)), msg: String) -> Nil

@target(javascript)
/// log a message at the error level
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

@target(erlang)
@external(erlang, "logger", "update_handler_config")
fn update_handler_config_context_erlang(
  handler id: Atom,
  config config: Dict(Atom, #(Atom, Dict(Atom, Context(t)))),
) -> Nil

@target(erlang)
@external(erlang, "logger", "update_handler_config")
fn update_handler_config_erlang(
  handler id: Atom,
  config config: Dict(Atom, Dynamic),
) -> Nil

@target(erlang)
@external(erlang, "logger", "set_handler_config")
fn set_handler_config_erlang(
  handler id: Atom,
  module name: Atom,
  config map: #(Atom, Dynamic),
) -> Nil

@target(erlang)
@external(erlang, "logger", "update_primary_config")
fn update_primary_config_erlang(config map: Dict(Atom, Dynamic)) -> Nil

// hacky workaround for gleam not supporting target specific type imports
@target(erlang)
type Atom =
  glatom.Atom

type Charlist =
  charlist.Charlist
