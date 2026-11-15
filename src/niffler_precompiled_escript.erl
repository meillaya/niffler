%% Entry point for the standalone `niffler` escript.
-module(niffler_precompiled_escript).

-export([main/1]).

main(Arguments) ->
    Binaries = [unicode:characters_to_binary(Argument) || Argument <- Arguments],
    niffler_precompiled:main_with_args(Binaries).
