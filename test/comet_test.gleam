import birl
import comet
import gleam/dict
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn metadata_test() {
  comet.configure(comet.new())
  comet.log()
  |> comet.attribute("lyric", "i'm feeling doooooown")
  |> comet.attribute("hot dog", ["flip flop"])
  |> comet.attribute("penny lane", #("fizz", "buzz", 1238))
  |> comet.attribute("time", birl.to_iso8601(birl.utc_now()))
  |> comet.debug("help!")
}
