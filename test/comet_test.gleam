import birl
import comet
import gleam/dict
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

type Attribute {
  Service(String)
  Latency(Float)
  StatusCode(Int)
  Success(Bool)
}

pub fn metadata_test() {
  comet.new()
  |> comet.level(comet.Debug)
  |> comet.with_attribute(STR("service", "comet"))
  |> comet.configure()

  comet.log()
  |> comet.attribute(STR("lyric", "i'm feeling doooooown"))
  |> comet.attribute(STR("time", birl.to_iso8601(birl.utc_now())))
  |> comet.info("help!")
}
