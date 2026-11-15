%% Erlang FFI for niffler.
%%
%% This module is compiled and published as part of the Hex package (Gleam
%% compiles every .erl file under src/). Keep it dependency-free beyond OTP.
-module(niffler_precompiled_ffi).

-export([
    os_type/0,
    system_architecture/0,
    nif_version/0,
    otp_release/0,
    wordsize/0,
    env/1,
    home_dir/0,
    user_cache_dir/1,
    cwd/0,
    path_separator/0,
    join_paths/1,
    dirname/1,
    basename/1,
    absname/1,
    read_file/1,
    write_file/2,
    write_file_exclusive/2,
    file_exists/1,
    file_size/1,
    ensure_dir/1,
    remove_file/1,
    rename/2,
    list_dir/1,
    set_file_mode/2,
    sha256_hex/1,
    sha256_file_hex/1,
    hash_tree/1,
    priv_dir/1,
    app_version/1,
    file_magic/1,
    http_get/3,
    tar_create_single/2,
    tar_inspect_gz/1,
    tar_extract_gz_member/2,
    tar_inspect_plain/1,
    tar_extract_plain_member/2,
    run/3,
    find_executable/1,
    sleep/1,
    halt_vm/1,
    plain_args/0,
    unique_id/0,
    timestamp/0,
    remove_tree/1,
    raise/2,
    print/1,
    eprint/1
]).

%%%-------------------------------------------------------------------
%%% Environment and platform
%%%-------------------------------------------------------------------

os_type() ->
    {Family, Name} = os:type(),
    {atom_to_binary(Family, utf8), atom_to_binary(Name, utf8)}.

system_architecture() ->
    to_bin(erlang:system_info(system_architecture)).

nif_version() ->
    to_bin(erlang:system_info(nif_version)).

otp_release() ->
    to_bin(erlang:system_info(otp_release)).

wordsize() ->
    erlang:system_info(wordsize).

env(Name) ->
    case os:getenv(to_list(Name)) of
        false -> none;
        Value -> {some, to_bin(Value)}
    end.

home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> <<>>;
                Path -> to_bin(Path)
            end;
        Path ->
            to_bin(Path)
    end.

user_cache_dir(AppName) ->
    try
        to_bin(filename:basedir(user_cache, to_list(AppName)))
    catch
        _:_ -> <<>>
    end.

cwd() ->
    {ok, Cwd} = file:get_cwd(),
    to_bin(Cwd).

path_separator() ->
    case os:type() of
        {win32, _} -> <<";">>;
        _ -> <<":">>
    end.

join_paths(Parts) ->
    to_bin(filename:join([to_list(Part) || Part <- Parts])).

dirname(Path) ->
    to_bin(filename:dirname(to_list(Path))).

basename(Path) ->
    to_bin(filename:basename(to_list(Path))).

absname(Path) ->
    to_bin(filename:absname(to_list(Path))).

%%%-------------------------------------------------------------------
%%% Files
%%%-------------------------------------------------------------------

read_file(Path) ->
    case file:read_file(to_list(Path)) of
        {ok, Binary} -> {ok, Binary};
        {error, Reason} -> {error, fmt(Reason)}
    end.

write_file(Path, Binary) ->
    case file:write_file(to_list(Path), Binary) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

write_file_exclusive(Path, Binary) ->
    case file:write_file(to_list(Path), Binary, [exclusive]) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

file_exists(Path) ->
    filelib:is_regular(to_list(Path)).

file_size(Path) ->
    case file:read_file_info(to_list(Path)) of
        {ok, Info} -> {ok, element(2, Info)};
        {error, Reason} -> {error, fmt(Reason)}
    end.

ensure_dir(Path) ->
    case filelib:ensure_dir(filename:join(to_list(Path), ".niffler-placeholder")) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

remove_file(Path) ->
    case file:delete(to_list(Path)) of
        ok -> {ok, nil};
        {error, enoent} -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

rename(From, To) ->
    case file:rename(to_list(From), to_list(To)) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

list_dir(Path) ->
    case file:list_dir(to_list(Path)) of
        {ok, Names} -> {ok, [to_bin(Name) || Name <- Names]};
        {error, Reason} -> {error, fmt(Reason)}
    end.

set_file_mode(Path, Mode) ->
    case file:change_mode(to_list(Path), Mode) of
        ok -> {ok, nil};
        {error, Reason} -> {error, fmt(Reason)}
    end.

%%%-------------------------------------------------------------------
%%% Hashes
%%%-------------------------------------------------------------------

sha256_hex(Binary) ->
    hex(crypto:hash(sha256, Binary)).

sha256_file_hex(Path) ->
    case file:open(to_list(Path), [read, binary, raw]) of
        {error, Reason} ->
            {error, fmt(Reason)};
        {ok, IoDevice} ->
            Result = hash_io(IoDevice, crypto:hash_init(sha256)),
            _ = file:close(IoDevice),
            case Result of
                {ok, Context} -> {ok, hex(crypto:hash_final(Context))};
                {error, Reason} -> {error, fmt(Reason)}
            end
    end.

hash_io(IoDevice, Context) ->
    case file:read(IoDevice, 1024 * 1024) of
        eof ->
            {ok, Context};
        {ok, Binary} ->
            hash_io(IoDevice, crypto:hash_update(Context, Binary));
        {error, Reason} ->
            {error, Reason}
    end.

%% Hash all regular files below Dir (sorted, relative paths + contents).
%% `target` and `.git` directories are skipped so a source tree fingerprint is
%% stable across local builds.
hash_tree(Dir) ->
    Root = to_list(Dir),
    case filelib:is_dir(Root) of
        false ->
            {error, <<"not a directory">>};
        true ->
            Files = walk_files(Root, "", []),
            Sorted = lists:sort(Files),
            Context = lists:foldl(
                fun(Relative, Acc) ->
                    {ok, Binary} = file:read_file(filename:join(Root, Relative)),
                    Acc1 = crypto:hash_update(Acc, to_bin(Relative)),
                    Acc2 = crypto:hash_update(Acc1, <<0>>),
                    crypto:hash_update(Acc2, Binary)
                end,
                crypto:hash_init(sha256),
                Sorted
            ),
            {ok, hex(crypto:hash_final(Context))}
    end.

walk_files(Root, RelativeDirectory, Accumulator) ->
    Directory = case RelativeDirectory of
        "" -> Root;
        _ -> filename:join(Root, RelativeDirectory)
    end,
    case file:list_dir(Directory) of
        {error, _} ->
            Accumulator;
        {ok, Names} ->
            lists:foldl(
                fun(Name, Acc) ->
                    FullPath = filename:join(Directory, Name),
                    Relative = case RelativeDirectory of
                        "" -> Name;
                        _ -> filename:join(RelativeDirectory, Name)
                    end,
                    case filelib:is_dir(FullPath) of
                        true ->
                            case lists:member(Name, ["target", ".git"]) of
                                true -> Acc;
                                false -> walk_files(Root, Relative, Acc)
                            end;
                        false ->
                            case filelib:is_regular(FullPath) of
                                true -> [Relative | Acc];
                                false -> Acc
                            end
                    end
                end,
                Accumulator,
                Names
            )
    end.

%%%-------------------------------------------------------------------
%%% OTP application metadata
%%%-------------------------------------------------------------------

priv_dir(AppName) ->
    try
        App = binary_to_atom(AppName, utf8),
        case code:priv_dir(App) of
            {error, bad_name} -> {error, <<"application not found on the code path">>};
            Dir when is_list(Dir) -> {ok, to_bin(Dir)}
        end
    catch
        _:_ -> {error, <<"invalid application name">>}
    end.

app_version(AppName) ->
    try
        App = binary_to_atom(AppName, utf8),
        case code:lib_dir(App) of
            {error, bad_name} ->
                {error, <<"application not found on the code path">>};
            LibDir ->
                AppFile = filename:join([LibDir, "ebin", binary_to_list(AppName) ++ ".app"]),
                case file:consult(AppFile) of
                    {ok, [{application, _App, Properties}]} ->
                        case proplists:get_value(vsn, Properties) of
                            undefined -> {error, <<"application version is missing">>};
                            Version -> {ok, to_bin(Version)}
                        end;
                    {error, Reason} ->
                        {error, fmt(Reason)};
                    _ ->
                        {error, <<"invalid .app file">>}
                end
        end
    catch
        _:_ -> {error, <<"invalid application name">>}
    end.

file_magic(Path) ->
    case file:open(to_list(Path), [read, binary, raw]) of
        {ok, IoDevice} ->
            Result = case file:read(IoDevice, 4) of
                {ok, <<16#7F, "ELF">>} -> <<"elf">>;
                {ok, <<16#FE, 16#ED, 16#FA, 16#CF>>} -> <<"macho">>;
                {ok, <<16#CF, 16#FA, 16#ED, 16#FE>>} -> <<"macho">>;
                {ok, <<16#CA, 16#FE, 16#BA, 16#BE>>} -> <<"macho">>;
                {ok, <<"MZ", _/binary>>} -> <<"pe">>;
                _ -> <<"unknown">>
            end,
            _ = file:close(IoDevice),
            Result;
        {error, _} ->
            <<"unknown">>
    end.

%%%-------------------------------------------------------------------
%%% HTTP(S) with manual redirects and strict verification
%%%-------------------------------------------------------------------

-define(MAX_BODY, 67108864).
-define(MAX_REDIRECTS, 5).

http_get(UrlBin, AllowInsecure, CaBundle) ->
    case prepare_apps() of
        ok ->
            request_loop(to_list(UrlBin), AllowInsecure, CaBundle, ?MAX_REDIRECTS);
        {error, Reason} ->
            {http_error, Reason}
    end.

prepare_apps() ->
    case application:ensure_all_started(inets) of
        {ok, _} ->
            case application:ensure_all_started(ssl) of
                {ok, _} -> ok;
                {error, Reason} -> {error, fmt(Reason)}
            end;
        {error, Reason} ->
            {error, fmt(Reason)}
    end.

request_loop(Url, AllowInsecure, CaBundle, RedirectsLeft) ->
    case valid_url(Url, AllowInsecure) of
        ok ->
            case do_request(Url, AllowInsecure, CaBundle) of
                {http_ok, Body} ->
                    {http_ok, 200, Body};
                {http_redirect, Location} when RedirectsLeft > 0 ->
                    Next = case uri_string:resolve(Location, Url) of
                        Resolved when is_list(Resolved) -> Resolved;
                        Resolved when is_binary(Resolved) -> binary_to_list(Resolved);
                        _ -> ""
                    end,
                    case Next of
                        "" -> {http_error, <<"redirect response without a usable Location header">>};
                        _ -> request_loop(Next, AllowInsecure, CaBundle, RedirectsLeft - 1)
                    end;
                {http_redirect, _} ->
                    {http_error, <<"too many HTTP redirects">>};
                {http_error, Reason} ->
                    {http_error, Reason}
            end;
        {error, Reason} ->
            {http_error, Reason}
    end.

valid_url(Url, AllowInsecure) ->
    case uri_string:parse(Url) of
        #{scheme := Scheme, host := Host} when Scheme =:= "https"; Scheme =:= <<"https">> ->
            case host_string(Host) of
                "" -> {error, <<"invalid URL host">>};
                _ -> ok
            end;
        #{scheme := Scheme, host := Host} when Scheme =:= "http"; Scheme =:= <<"http">> ->
            case {AllowInsecure, is_loopback(host_string(Host))} of
                {true, true} -> ok;
                _ -> {error, <<"refusing insecure HTTP URL (test-only override is enabled only for loopback hosts)">>}
            end;
        _ ->
            {error, <<"invalid or unsupported URL">>}
    end.

host_string(Host) when is_binary(Host) -> binary_to_list(Host);
host_string(Host) when is_list(Host) -> Host;
host_string(_) -> "".

is_loopback("localhost") -> true;
is_loopback("127.0.0.1") -> true;
is_loopback("::1") -> true;
is_loopback(_) -> false.

do_request(Url, AllowInsecure, CaBundle) ->
    Headers = [{"user-agent", "niffler_precompiled/0.1.0"}],
    HttpOptions = request_options(Url, AllowInsecure, CaBundle),
    RequestOptions = [{body_format, binary}, {max_body_size, ?MAX_BODY}],
    try httpc:request(get, {Url, Headers}, HttpOptions, RequestOptions) of
        {ok, {{_, 200, _}, ResponseHeaders, Body}} ->
            case declared_too_large(ResponseHeaders) of
                true -> {http_error, <<"downloaded body is too large">>};
                false ->
                    case byte_size(Body) =< ?MAX_BODY of
                        true -> {http_ok, Body};
                        false -> {http_error, <<"downloaded body is too large">>}
                    end
            end;
        {ok, {{_, Status, _}, ResponseHeaders, _Body}} when Status >= 300, Status < 400 ->
            case header_value("location", ResponseHeaders) of
                undefined -> {http_error, <<"redirect without Location header">>};
                Location -> {http_redirect, Location}
            end;
        {ok, {{_, Status, _}, _Headers, _Body}} ->
            {http_error, <<"HTTP ", (integer_to_binary(Status))/binary>>};
        {error, Reason} ->
            {http_error, fmt(Reason)}
    catch
        Class:Error ->
            {http_error, fmt({Class, Error})}
    end.

request_options(Url, AllowInsecure, CaBundle) ->
    Base = [
        {timeout, 60000},
        {connect_timeout, 15000},
        {autoredirect, false}
    ],
    case uri_string:parse(Url) of
        #{scheme := "https"} ->
            Base ++ [{ssl, ssl_options(CaBundle)}];
        #{scheme := "http"} when AllowInsecure ->
            Base;
        _ ->
            Base
    end.

ssl_options(CaBundle) ->
    Cacerts =
        case CaBundle of
            <<>> ->
                try public_key:cacerts_get() of
                    Certs when is_list(Certs), Certs =/= [] -> [{cacerts, Certs}];
                    _ -> error(no_cacerts)
                catch
                    _:_ -> error(no_cacerts)
                end;
            Path ->
                [{cacertfile, to_list(Path)}]
        end,
    [
        {verify, verify_peer},
        {depth, 3},
        {customize_hostname_check, [
            {match_fun, public_key:pkix_verify_hostname_match_fun(https)}
        ]}
    ] ++ Cacerts.

declared_too_large(Headers) ->
    case header_value("content-length", Headers) of
        undefined ->
            false;
        Value ->
            case string:to_integer(Value) of
                {Size, _} when is_integer(Size) -> Size > ?MAX_BODY;
                _ -> false
            end
    end.

header_value(Name, Headers) ->
    case lists:filter(
        fun({Key, _Value}) ->
            string:lowercase(to_list(Key)) =:= Name
        end,
        Headers
    ) of
        [{_Key, Value} | _] -> to_list(Value);
        [] -> undefined
    end.

%%%-------------------------------------------------------------------
%%% tar.gz creation and inspection
%%%-------------------------------------------------------------------

%% Create a deterministic gzip'd tar archive containing exactly one regular
%% file. Mode 0755, mtime 0, uid/gid 0, empty owner names.
tar_create_single(Name, Contents) when is_binary(Name), is_binary(Contents) ->
    case valid_archive_name(Name) of
        false ->
            {error, <<"invalid archive member name">>};
        true ->
            Header0 = tar_header(Name, byte_size(Contents)),
            Checksum = tar_checksum(Header0),
            Header = set_checksum(Header0, Checksum),
            Padding = binary:copy(<<0>>, padding(byte_size(Contents))),
            Archive = <<Header/binary, Contents/binary, Padding/binary, (binary:copy(<<0>>, 1024))/binary>>,
            {ok, zlib:gzip(Archive)}
    end.

valid_archive_name(Name) ->
    byte_size(Name) > 0
        andalso byte_size(Name) < 100
        andalso binary:match(Name, <<"/">>) =:= nomatch
        andalso binary:match(Name, <<"\\">>) =:= nomatch
        andalso binary:match(Name, <<"..">>) =:= nomatch.

tar_header(Name, Size) ->
    <<
        (pad_binary(Name, 100, 0))/binary,
        (octal_field(8#755, 8))/binary,
        (octal_field(0, 8))/binary,
        (octal_field(0, 8))/binary,
        (octal_field(Size, 12))/binary,
        (octal_field(0, 12))/binary,
        (binary:copy(<<" ">>, 8))/binary,
        "0",
        (binary:copy(<<0>>, 100))/binary,
        "ustar",
        0,
        "00",
        (binary:copy(<<0>>, 32))/binary,
        (binary:copy(<<0>>, 32))/binary,
        (octal_field(0, 8))/binary,
        (octal_field(0, 8))/binary,
        (binary:copy(<<0>>, 155))/binary,
        (binary:copy(<<0>>, 12))/binary
    >>.

tar_checksum(Header) ->
    lists:sum([Byte || <<Byte>> <= Header]).

set_checksum(Header, Checksum) ->
    <<Before:148/binary, _Old:8/binary, After/binary>> = Header,
    Field = checksum_field(Checksum),
    <<Before/binary, Field/binary, After/binary>>.

checksum_field(Checksum) ->
    Digits = integer_to_binary(Checksum, 8),
    Padding = 6 - byte_size(Digits),
    <<(binary:copy(<<"0">>, Padding))/binary, Digits/binary, 0, " ">>.

padding(Size) ->
    (512 - (Size rem 512)) rem 512.

octal_field(Value, Width) ->
    Digits = integer_to_binary(Value, 8),
    Padding = Width - 1 - byte_size(Digits),
    <<(binary:copy(<<"0">>, Padding))/binary, Digits/binary, 0>>.

pad_binary(Binary, Width, PaddingByte) ->
    Padding = Width - byte_size(Binary),
    <<Binary/binary, (binary:copy(<<PaddingByte>>, Padding))/binary>>.

tar_inspect_gz(Binary) ->
    inspect_tar(Binary, [compressed, verbose]).

tar_extract_gz_member(Binary, Name) ->
    extract_tar_member(Binary, Name, [compressed, memory]).

tar_inspect_plain(Binary) ->
    inspect_tar(Binary, [verbose]).

tar_extract_plain_member(Binary, Name) ->
    extract_tar_member(Binary, Name, [memory]).

inspect_tar(Binary, Options) ->
    try erl_tar:table({binary, Binary}, Options) of
        {ok, Entries} ->
            {ok, [
                {tar_entry, to_bin(Name), type_bin(Type), Size}
             || {Name, Type, Size, _MTime, _Mode, _Uid, _Gid} <- Entries
            ]};
        {error, Reason} ->
            {error, fmt(Reason)}
    catch
        Class:Error ->
            {error, fmt({Class, Error})}
    end.

type_bin(regular) -> <<"regular">>;
type_bin(directory) -> <<"directory">>;
type_bin(symlink) -> <<"symlink">>;
type_bin(link) -> <<"link">>;
type_bin(Other) -> to_bin(io_lib:format("~p", [Other])).

extract_tar_member(Binary, Name, Options) ->
    try erl_tar:extract({binary, Binary}, Options) of
        {ok, Entries} ->
            case lists:keyfind(to_list(Name), 1, Entries) of
                {_, Contents} when is_binary(Contents) -> {ok, Contents};
                _ -> {error, <<"archive member not found">>}
            end;
        {error, Reason} ->
            {error, fmt(Reason)}
    catch
        Class:Error ->
            {error, fmt({Class, Error})}
    end.

%%%-------------------------------------------------------------------
%%% Processes
%%%-------------------------------------------------------------------

run(Executable, Arguments, WorkingDirectory) ->
    Exe = resolve_executable(to_list(Executable)),
    case Exe of
        false ->
            {-1, <<"executable not found: ", (to_bin(Executable))/binary>>};
        Path ->
            Args = [to_list(Argument) || Argument <- Arguments],
            Port = open_port(
                {spawn_executable, Path},
                [
                    binary,
                    exit_status,
                    stderr_to_stdout,
                    use_stdio,
                    {args, Args},
                    {cd, to_list(WorkingDirectory)}
                ]
            ),
            collect_port(Port, [])
    end.

resolve_executable(Path) ->
    case filename:pathtype(Path) of
        absolute ->
            case filelib:is_regular(Path) of
                true -> Path;
                false -> false
            end;
        _ ->
            os:find_executable(Path)
    end.

collect_port(Port, Accumulator) ->
    receive
        {Port, {data, Data}} ->
            collect_port(Port, [Data | Accumulator]);
        {Port, {exit_status, Status}} ->
            {Status, iolist_to_binary(lists:reverse(Accumulator))}
    after 30 * 60 * 1000 ->
        port_close(Port),
        {-1, iolist_to_binary(lists:reverse(Accumulator))}
    end.

find_executable(Name) ->
    case os:find_executable(to_list(Name)) of
        false -> none;
        Path -> {some, to_bin(Path)}
    end.

sleep(Milliseconds) ->
    timer:sleep(Milliseconds),
    nil.

halt_vm(Code) ->
    erlang:halt(Code).

plain_args() ->
    [to_bin(Argument) || Argument <- init:get_plain_arguments()].

unique_id() ->
    erlang:unique_integer([positive]).

timestamp() ->
    erlang:system_time(millisecond).

remove_tree(Path) ->
    PathList = to_list(Path),
    case filelib:is_dir(PathList) of
        true ->
            case file:list_dir(PathList) of
                {ok, Names} ->
                    lists:foreach(
                        fun(Name) -> remove_tree(filename:join(PathList, Name)) end,
                        Names
                    ),
                    case file:del_dir(PathList) of
                        ok -> {ok, nil};
                        {error, enoent} -> {ok, nil};
                        {error, Reason} -> {error, fmt(Reason)}
                    end;
                {error, Reason} ->
                    {error, fmt(Reason)}
            end;
        false ->
            case file:delete(PathList) of
                ok -> {ok, nil};
                {error, enoent} -> {ok, nil};
                {error, Reason} -> {error, fmt(Reason)}
            end
    end.

raise(Package, Message) ->
    io:put_chars(standard_error, [Message, "\n"]),
    erlang:error({niffler, Package, Message}).

print(Message) ->
    io:put_chars(Message),
    nil.

eprint(Message) ->
    io:put_chars(standard_error, Message),
    nil.

%%%-------------------------------------------------------------------
%%% Helpers
%%%-------------------------------------------------------------------

to_bin(Value) when is_binary(Value) -> Value;
to_bin(Value) when is_list(Value) -> unicode:characters_to_binary(Value);
to_bin(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
to_bin(Value) when is_integer(Value) -> integer_to_binary(Value).

to_list(Value) when is_list(Value) -> Value;
to_list(Value) when is_binary(Value) -> unicode:characters_to_list(Value);
to_list(Value) when is_atom(Value) -> atom_to_list(Value).

fmt(Reason) ->
    to_bin(io_lib:format("~p", [Reason])).

hex(Binary) ->
    << <<(hex_digit(N))>> || <<N:4>> <= Binary >>.

hex_digit(N) when N < 10 -> $0 + N;
hex_digit(N) -> $a + N - 10.
