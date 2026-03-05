-module('erlang.util.Regex').

-include("clojerl.hrl").

-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , run/3
        , replace/3
        , replace/4
        , quote/1
        , split/3
        ]).
-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE   => ?M
                 , pattern => binary()
                 }.

-spec ?CONSTRUCTOR(binary()) -> type().
?CONSTRUCTOR(Pattern) when is_binary(Pattern) ->
  #{ ?TYPE   => ?M
   , pattern => Pattern
   }.

-spec run(type(), binary(), [term()]) ->
  {match, term()} | match | nomatch | {error, term()}.
run(#{?TYPE := ?M} = Re, Str, Opts) ->
  re:run(Str, compiled(Re), Opts).

-spec replace(type(), binary(), binary()) -> binary().
replace(#{?TYPE := ?M} = Regex, Str, Replacement) ->
  replace(Regex, Str, Replacement, [global, {return, binary}]).

-spec replace(type(), binary(), binary(), [term()]) -> binary().
replace(Regex, Str, Replacement, Opts) when is_binary(Regex) ->
  replace(?CONSTRUCTOR(Regex), Str, Replacement, Opts);
replace(#{?TYPE := ?M} = Re, Str, Replacement, Opts) ->
  re:replace(Str, compiled(Re), Replacement, [{return, binary} | Opts]).

-spec quote(binary()) -> binary().
quote(Regex) when is_binary(Regex) ->
  do_quote(Regex, <<>>).

-spec split(type(), binary(), [term()]) -> [binary()].
split(Regex, Str, Opts) when is_binary(Regex) ->
  split(?CONSTRUCTOR(Regex), Str, Opts);
split(#{?TYPE := ?M} = Re, Str, Opts) ->
  re:split(Str, compiled(Re), Opts).

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

hash(#{?TYPE := ?M, pattern := Pattern}) -> erlang:phash2(Pattern).

str(#{?TYPE := ?M, pattern := Pattern}) -> <<"#\"", Pattern/binary, "\"">>.

%%------------------------------------------------------------------------------
%% Helper functions
%%------------------------------------------------------------------------------

-spec compiled(type()) -> any().
compiled(#{?TYPE := ?M, pattern := Pattern}) ->
  Key = {?M, Pattern},
  try persistent_term:get(Key)
  catch error:badarg ->
    {ok, Regex} = re:compile(Pattern),
    persistent_term:put(Key, Regex),
    Regex
  end.

-spec do_quote(binary(), binary()) -> binary().
do_quote(<<>>, Acc) ->
  Acc;
do_quote(<<Ch/utf8, Rest/binary>>, Acc) ->
  NewCh = case Ch of
            $$  -> <<"\\$">>;
            $\\ -> <<"\\\\">>;
            _   -> <<Ch/utf8>>
          end,
  do_quote(Rest, <<Acc/binary, NewCh/binary>>).
