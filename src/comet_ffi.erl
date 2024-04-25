-module(comet_ffi).
-export([get_attribute_atom/1, configure/1, debug/2, info/2, warning/2, error/2, allow_metadata_filter/1, deny_metadata_filter/1, add_handler/1]).

debug(Metadata, Message) -> log(debug, Message, Metadata).
info(Metadata, Message) -> log(info, Message, Metadata).
warning(Metadata, Message) -> log(warning, Message, Metadata).
error(Metadata, Message) -> log(error, Message, Metadata).
log(Level, Message, Metadata) -> logger:log(Level, Message, Metadata).

configure(Config) ->
    {_Name, _LevelText, _Formatter,  MinLevel} = Config,
    ok = logger:update_primary_config(#{
        level => MinLevel,
        filter_default => log,
        filters => [],
        metadata => #{}
            }),
    ok = logger:update_handler_config(default, #{
        formatter => {comet, [#{config => Config}]}
    }),
    nil.

add_handler(Handler) ->
    {Module, MinLevel, Formatter, Filters, Metadata} = Handler,
    ok = logger:add_handler(Module, #{
        level => MinLevel,
        filter_default => log,
        filters => Filters,
        formatter => Formatter,
        metadata => Metadata
    }),
    nil.

allow_metadata_filter(Domains) ->
   {domain, {fun logger_filters:domain/2, {log, sub, Domains}}}.

deny_metadata_filter(Domains) ->
    {domain, {fun logger_filters:domain/2, {stop, sub, Domains}}}.

get_attribute_atom(Attribute) ->
    [First|_] = tuple_to_list(Attribute),
    First.
