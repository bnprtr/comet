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

pub opaque type Configuration {
  Configuration(
    level_text: fn(Level) -> String,
    formatter: Formatter,
    min_level: Level,
    filters: Filters,
    metadata: Metadata,
    outputs: List(Output),
  )
}

pub fn new() -> Configuration {
  Configuration(
    level_text,
    text_formatter,
    Info,
    dict.new(),
    new_metadata(),
    [],
  )
}

@external(erlang, "comet_ffi", "configure")
@external(javascript, "./logs.mjs", "set_config")
pub fn configure(config: Configuration) -> Nil

pub type Level {
  Debug
  Info
  Warn
  Err
  Panic
}

pub fn level_text(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warn -> "warn"
    Err -> "error"
    Panic -> "panic"
  }
}

pub fn level_priority(level: Level) -> Int {
  case level {
    Debug -> 1
    Info -> 2
    Warn -> 3
    Err -> 4
    Panic -> 5
  }
}

pub type Entry {
  Entry(level: Level, message: String, metadata: Metadata)
}

@target(javascript)
@external(javascript, "./logs.mjs", "insert_attribute")
pub fn attribute(md: Metadata, key: String, value: e) -> Metadata

@target(erlang)
pub fn attribute(md: Metadata, key: String, value: e) -> Metadata {
  dict.insert(md, key_name(key), dynamic.from(value))
}

@target(erlang)
pub fn format(log: Dict(Atom, Dynamic), config) -> List(String) {
  let level: Level = extract_level_from_erlang_log(log)
  let metadata: Metadata = extract_metadata_from_erlang_log(log)
  let msg: String = extract_msg_from_erlang_log(log)

  ["level:", level_text(level), " | ", msg, string.inspect(metadata)]
}

@target(erlang)
fn extract_metadata_from_erlang_log(log: Dict(Atom, Dynamic)) -> Metadata {
  case dict.get(log, key_name("meta")) {
    Ok(value) ->
      case dynamic.dict(atom.from_dynamic, dynamic.dynamic)(value) {
        Ok(md) -> md
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

@external(javascript, "./logs.mjs", "new_metadata")
fn new_metadata() -> Metadata {
  dict.new()
}

@target(javascript)
pub type Json

@target(javascript)
type Metadata =
  Json

@target(erlang)
type Metadata =
  Dict(Atom, Dynamic)

type Formatter =
  fn(Entry) -> String

@target(erlang)
fn formatter_wrapper(entry: #(Level, String, Metadata)) -> Entry {
  Entry(level: entry.0, message: entry.1, metadata: entry.2)
}

fn text_formatter(entry: Entry) -> String {
  todo
}

type Output =
  fn(Entry) -> Nil

type Filter =
  fn(Entry) -> Bool

@target(erlang)
type Filters =
  Dict(Atom, Filter)

@target(javascript)
type Filters =
  Dict(String, Filter)

pub fn with_filter(
  config: Configuration,
  name: String,
  filter: Filter,
) -> Configuration {
  Configuration(
    ..config,
    filters: dict.insert(config.filters, key_name(name), filter),
  )
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

pub fn log() -> Metadata {
  new_metadata()
}

@external(erlang, "comet_ffi", "debug")
@external(javascript, "./logs.mjs", "debug")
pub fn debug(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "info")
@external(javascript, "./logs.mjs", "info")
pub fn info(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "warn")
@external(javascript, "./logs.mjs", "warn")
pub fn warn(md: Metadata, msg: String) -> Nil

@external(erlang, "comet_ffi", "error")
@external(javascript, "./logs.mjs", "error")
pub fn error(md: Metadata, msg: String) -> Nil
