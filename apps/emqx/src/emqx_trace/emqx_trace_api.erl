%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_trace_api).
-include_lib("emqx/include/logger.hrl").
-include_lib("kernel/include/file.hrl").

%% API
-export([ list_trace/2
        , create_trace/2
        , update_trace/2
        , delete_trace/2
        , clear_traces/2
        , download_zip_log/2
        , stream_log_file/2
]).
-export([ read_trace_file/3
        , get_trace_size/0
        ]).

-define(TO_BIN(_B_), iolist_to_binary(_B_)).
-define(NOT_FOUND(N), {error, 'NOT_FOUND', ?TO_BIN([N, " NOT FOUND"])}).

list_trace(_, _Params) ->
    case emqx_trace:list() of
        [] -> {ok, []};
        List0 ->
            List = lists:sort(fun(#{start_at := A}, #{start_at := B}) -> A > B end, List0),
            Nodes = mria_mnesia:running_nodes(),
            TraceSize = cluster_call(?MODULE, get_trace_size, [], 30000),
            AllFileSize = lists:foldl(fun(F, Acc) -> maps:merge(Acc, F) end, #{}, TraceSize),
            Now = erlang:system_time(second),
            Traces =
                lists:map(fun(Trace = #{name := Name, start_at := Start,
                    end_at := End, enable := Enable, type := Type, filter := Filter}) ->
                    FileName = emqx_trace:filename(Name, Start),
                    LogSize = collect_file_size(Nodes, FileName, AllFileSize),
                    Trace0 = maps:without([enable, filter], Trace),
                    Trace0#{ log_size => LogSize
                           , Type => Filter
                           , start_at => list_to_binary(calendar:system_time_to_rfc3339(Start))
                           , end_at => list_to_binary(calendar:system_time_to_rfc3339(End))
                           , status => status(Enable, Start, End, Now)
                           }
                          end, emqx_trace:format(List)),
            {ok, Traces}
    end.

create_trace(_, Param) ->
    case emqx_trace:create(Param) of
        ok -> ok;
        {error, {already_existed, Name}} ->
            {error, 'ALREADY_EXISTED', ?TO_BIN([Name, "Already Exists"])};
        {error, {duplicate_condition, Name}} ->
            {error, 'DUPLICATE_CONDITION', ?TO_BIN([Name, "Duplication Condition"])};
        {error, Reason} ->
            {error, 'INCORRECT_PARAMS', ?TO_BIN(Reason)}
    end.

delete_trace(#{name := Name}, _Param) ->
    case emqx_trace:delete(Name) of
        ok -> ok;
        {error, not_found} -> ?NOT_FOUND(Name)
    end.

clear_traces(_, _) ->
    emqx_trace:clear().

update_trace(#{name := Name, operation := Operation}, _Param) ->
    Enable = case Operation of disable -> false; enable -> true end,
    case emqx_trace:update(Name, Enable) of
        ok -> {ok, #{enable => Enable, name => Name}};
        {error, not_found} -> ?NOT_FOUND(Name)
    end.

%% if HTTP request headers include accept-encoding: gzip and file size > 300 bytes.
%% cowboy_compress_h will auto encode gzip format.
download_zip_log(#{name := Name}, _Param) ->
    case emqx_trace:get_trace_filename(Name) of
        {ok, TraceLog} ->
            TraceFiles = collect_trace_file(TraceLog),
            ZipDir = emqx_trace:zip_dir(),
            Zips = group_trace_file(ZipDir, TraceLog, TraceFiles),
            ZipFileName = ZipDir ++ binary_to_list(Name) ++ ".zip",
            {ok, ZipFile} = zip:zip(ZipFileName, Zips, [{cwd, ZipDir}]),
            emqx_trace:delete_files_after_send(ZipFileName, Zips),
            {ok, ZipFile};
        {error, Reason} ->
            {error, Reason}
    end.

group_trace_file(ZipDir, TraceLog, TraceFiles) ->
    lists:foldl(fun(Res, Acc) ->
        case Res of
            {ok, Node, Bin} ->
                ZipName = ZipDir ++ Node ++ "-" ++ TraceLog,
                ok = file:write_file(ZipName, Bin),
                [Node ++ "-" ++ TraceLog | Acc];
            {error, Node, Reason} ->
                ?LOG(error, "download trace log error:~p", [{Node, TraceLog, Reason}]),
                Acc
        end
                end, [], TraceFiles).

collect_trace_file(TraceLog) ->
    cluster_call(emqx_trace, trace_file, [TraceLog], 60000).

cluster_call(Mod, Fun, Args, Timeout) ->
    Nodes = mria_mnesia:running_nodes(),
    {GoodRes, BadNodes} = rpc:multicall(Nodes, Mod, Fun, Args, Timeout),
    BadNodes =/= [] andalso ?LOG(error, "rpc call failed on ~p ~p", [BadNodes, {Mod, Fun, Args}]),
    GoodRes.

stream_log_file(#{name := Name}, Params) ->
    Node0 = proplists:get_value(<<"node">>, Params, atom_to_binary(node())),
    Position0 = proplists:get_value(<<"position">>, Params, <<"0">>),
    Bytes0 = proplists:get_value(<<"bytes">>, Params, <<"1000">>),
    case to_node(Node0) of
        {ok, Node} ->
            Position = binary_to_integer(Position0),
            Bytes = binary_to_integer(Bytes0),
            case rpc:call(Node, ?MODULE, read_trace_file, [Name, Position, Bytes]) of
                {ok, Bin} ->
                    Meta = #{<<"position">> => Position + byte_size(Bin), <<"bytes">> => Bytes},
                    {ok, #{meta => Meta, items => Bin}};
                {eof, Size} ->
                    Meta = #{<<"position">> => Size, <<"bytes">> => Bytes},
                    {ok, #{meta => Meta, items => <<"">>}};
                {error, Reason} ->
                    logger:log(error, "read_file_failed by ~p", [{Name, Reason, Position, Bytes}]),
                    {error, Reason};
                {badrpc, nodedown} ->
                    {error, "BadRpc node down"}
            end;
        {error, Reason} -> {error, Reason}
    end.

get_trace_size() ->
    TraceDir = emqx_trace:trace_dir(),
    Node = node(),
    case file:list_dir(TraceDir) of
        {ok, AllFiles} ->
            lists:foldl(fun(File, Acc) ->
                FullFileName = filename:join(TraceDir, File),
                Acc#{{Node, File} => filelib:file_size(FullFileName)}
                        end, #{}, lists:delete("zip", AllFiles));
        _ -> #{}
    end.

%% this is an rpc call for stream_log_file/2
read_trace_file(Name, Position, Limit) ->
    TraceDir = emqx_trace:trace_dir(),
    {ok, AllFiles} = file:list_dir(TraceDir),
    TracePrefix = "trace_" ++ binary_to_list(Name) ++ "_",
    Filter = fun(FileName) -> nomatch =/= string:prefix(FileName, TracePrefix) end,
    case lists:filter(Filter, AllFiles) of
        [TraceFile] ->
            TracePath = filename:join([TraceDir, TraceFile]),
            read_file(TracePath, Position, Limit);
        [] -> {error, not_found}
    end.

read_file(Path, Offset, Bytes) ->
    {ok, IoDevice} = file:open(Path, [read, raw, binary]),
    try
        _ = case Offset of
                0 -> ok;
                _ -> file:position(IoDevice, {bof, Offset})
            end,
        case file:read(IoDevice, Bytes) of
            {ok, Bin} -> {ok, Bin};
            {error, Reason} -> {error, Reason};
            eof ->
                {ok, #file_info{size = Size}} = file:read_file_info(IoDevice),
                {eof, Size}
        end
    after
        file:close(IoDevice)
    end.

to_node(Node) ->
    try {ok, binary_to_existing_atom(Node)}
    catch _:_ ->
        {error, "node not found"}
    end.

collect_file_size(Nodes, FileName, AllFiles) ->
    lists:foldl(fun(Node, Acc) ->
        Size = maps:get({Node, FileName}, AllFiles, 0),
        Acc#{Node => Size}
                end, #{}, Nodes).

%% status(false, _Start, End, Now) when End > Now -> <<"stopped">>;
status(false, _Start, _End, _Now) -> <<"stopped">>;
status(true, Start, _End, Now) when Now < Start -> <<"waiting">>;
status(true, _Start, End, Now) when Now >= End -> <<"stopped">>;
status(true, _Start, _End, _Now) -> <<"running">>.
