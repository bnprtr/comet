-module(comet_ffi).
-export([get_attribute_atom/1]).

get_attribute_atom(Attribute) ->
    [First | _] = tuple_to_list(Attribute),
    First.
