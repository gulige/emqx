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

-module(emqx_authentication_SUITE).

-behaviour(hocon_schema).
-behaviour(emqx_authentication).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("typerefl/include/types.hrl").

-export([ roots/0, fields/1 ]).

-export([ create/2
        , update/2
        , authenticate/2
        , destroy/1
        , check_config/1
        ]).

-define(AUTHN, emqx_authentication).
-define(config(KEY), (fun() -> {KEY, _V_} = lists:keyfind(KEY, 1, Config), _V_ end)()).

%%------------------------------------------------------------------------------
%% Hocon Schema
%%------------------------------------------------------------------------------

roots() -> [{config, #{type => hoconsc:union([hoconsc:ref(type1), hoconsc:ref(type2)])}}].

fields(type1) ->
    [ {mechanism,               {enum, ['password-based']}}
    , {backend,                 {enum, ['built-in-database']}}
    , {enable,                  fun enable/1}
    ];

fields(type2) ->
    [ {mechanism,               {enum, ['password-based']}}
    , {backend,                 {enum, ['mysql']}}
    , {enable,                  fun enable/1}
    ].

enable(type) -> boolean();
enable(default) -> true;
enable(_) -> undefined.

%%------------------------------------------------------------------------------
%% Callbacks
%%------------------------------------------------------------------------------

check_config(C) ->
    #{config := R} =
        hocon_schema:check_plain(?MODULE, #{<<"config">> => C},
                                 #{atom_key => true}),
    R.

create(_AuthenticatorID, _Config) ->
    {ok, #{mark => 1}}.

update(_Config, _State) ->
    {ok, #{mark => 2}}.

authenticate(#{username := <<"good">>}, _State) ->
    {ok, #{is_superuser => true}};
authenticate(#{username := _}, _State) ->
    {error, bad_username_or_password}.

destroy(_State) ->
    ok.

all() ->
    emqx_common_test_helpers:all(?MODULE).

init_per_suite(Config) ->
    application:set_env(ekka, strict_mode, true),
    emqx_common_test_helpers:start_apps([]),
    Config.

end_per_suite(_) ->
    emqx_common_test_helpers:stop_apps([]),
    ok.

init_per_testcase(Case, Config) ->
    ?MODULE:Case({'init', Config}).

end_per_testcase(Case, Config) ->
    _ = ?MODULE:Case({'end', Config}),
    ok.


t_chain({_, Config}) -> Config;

t_chain(Config) when is_list(Config) ->
    % CRUD of authentication chain
    ChainName = 'test',
    ?assertMatch({ok, []}, ?AUTHN:list_chains()),
    ?assertMatch({ok, []}, ?AUTHN:list_chain_names()),
    ?assertMatch({ok, #{name := ChainName, authenticators := []}}, ?AUTHN:create_chain(ChainName)),
    ?assertEqual({error, {already_exists, {chain, ChainName}}}, ?AUTHN:create_chain(ChainName)),
    ?assertMatch({ok, #{name := ChainName, authenticators := []}}, ?AUTHN:lookup_chain(ChainName)),
    ?assertMatch({ok, [#{name := ChainName}]}, ?AUTHN:list_chains()),
    ?assertEqual({ok, [ChainName]}, ?AUTHN:list_chain_names()),
    ?assertEqual(ok, ?AUTHN:delete_chain(ChainName)),
    ?assertMatch({error, {not_found, {chain, ChainName}}}, ?AUTHN:lookup_chain(ChainName)),
    ok.


t_authenticator({'init', Config}) ->
    [{"auth1", {'password-based', 'built-in-database'}},
     {"auth2", {'password-based', mysql}} | Config];

t_authenticator(Config) when is_list(Config) ->
    ChainName = 'test',
    AuthenticatorConfig1 = #{mechanism => 'password-based',
                             backend => 'built-in-database',
                             enable => true},

    % Create an authenticator when the authentication chain does not exist
    ?assertEqual(
       {error, {not_found, {chain, ChainName}}},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig1)),

    ?AUTHN:create_chain(ChainName),
    % Create an authenticator when the provider does not exist

    ?assertEqual(
       {error, no_available_provider},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig1)),

    AuthNType1 = ?config("auth1"),
    register_provider(AuthNType1, ?MODULE),
    ID1 = <<"password-based:built-in-database">>,

    % CRUD of authencaticator
    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 1}}},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig1)),

    ?assertMatch({ok, #{id := ID1}}, ?AUTHN:lookup_authenticator(ChainName, ID1)),
    ?assertMatch({ok, [#{id := ID1}]}, ?AUTHN:list_authenticators(ChainName)),

    ?assertEqual(
       {error, {already_exists, {authenticator, ID1}}},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig1)),

    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 2}}},
       ?AUTHN:update_authenticator(ChainName, ID1, AuthenticatorConfig1)),

    ?assertEqual(ok, ?AUTHN:delete_authenticator(ChainName, ID1)),

    ?assertEqual(
       {error, {not_found, {authenticator, ID1}}},
       ?AUTHN:update_authenticator(ChainName, ID1, AuthenticatorConfig1)),

    ?assertMatch({ok, []}, ?AUTHN:list_authenticators(ChainName)),

    % Multiple authenticators exist at the same time
    AuthNType2 = ?config("auth2"),
    register_provider(AuthNType2, ?MODULE),
    ID2 = <<"password-based:mysql">>,
    AuthenticatorConfig2 = #{mechanism => 'password-based',
                             backend => mysql,
                             enable => true},

    ?assertMatch(
       {ok, #{id := ID1}},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig1)),

    ?assertMatch(
       {ok, #{id := ID2}},
       ?AUTHN:create_authenticator(ChainName, AuthenticatorConfig2)),

    % Move authenticator
    ?assertMatch({ok, [#{id := ID1}, #{id := ID2}]}, ?AUTHN:list_authenticators(ChainName)),

    ?assertEqual(ok, ?AUTHN:move_authenticator(ChainName, ID2, top)),
    ?assertMatch({ok, [#{id := ID2}, #{id := ID1}]}, ?AUTHN:list_authenticators(ChainName)),

    ?assertEqual(ok, ?AUTHN:move_authenticator(ChainName, ID2, bottom)),
    ?assertMatch({ok, [#{id := ID1}, #{id := ID2}]}, ?AUTHN:list_authenticators(ChainName)),

    ?assertEqual(ok, ?AUTHN:move_authenticator(ChainName, ID2, {before, ID1})),
    ?assertMatch({ok, [#{id := ID2}, #{id := ID1}]}, ?AUTHN:list_authenticators(ChainName));

t_authenticator({'end', Config}) ->
    ?AUTHN:delete_chain(test),
    ?AUTHN:deregister_providers([?config("auth1"), ?config("auth2")]),
    ok.


t_authenticate({init, Config}) ->
    [{listener_id, 'tcp:default'},
     {authn_type, {'password-based', 'built-in-database'}} | Config];

t_authenticate(Config) when is_list(Config) ->
    ListenerID = ?config(listener_id),
    AuthNType = ?config(authn_type),
    ClientInfo = #{zone => default,
                   listener => ListenerID,
                   protocol => mqtt,
                   username => <<"good">>,
			       password => <<"any">>},
    ?assertEqual({ok, #{is_superuser => false}}, emqx_access_control:authenticate(ClientInfo)),

    register_provider(AuthNType, ?MODULE),

    AuthenticatorConfig = #{mechanism => 'password-based',
                            backend => 'built-in-database',
                            enable => true},
    ?AUTHN:create_chain(ListenerID),
    ?assertMatch({ok, _}, ?AUTHN:create_authenticator(ListenerID, AuthenticatorConfig)),

    ?assertEqual(
       {ok, #{is_superuser => true}},
       emqx_access_control:authenticate(ClientInfo)),

    ?assertEqual(
       {error, bad_username_or_password},
       emqx_access_control:authenticate(ClientInfo#{username => <<"bad">>}));

t_authenticate({'end', Config}) ->
    ?AUTHN:delete_chain(?config(listener_id)),
    ?AUTHN:deregister_provider(?config(authn_type)),
    ok.


t_update_config({init, Config}) ->
    Global = 'mqtt:global',
    AuthNType1 = {'password-based', 'built-in-database'},
    AuthNType2 = {'password-based', mysql},
    [{global, Global},
     {"auth1", AuthNType1},
     {"auth2", AuthNType2} | Config];

t_update_config(Config) when is_list(Config) ->
    emqx_config_handler:add_handler([authentication], emqx_authentication),
    ok = register_provider(?config("auth1"), ?MODULE),
    ok = register_provider(?config("auth2"), ?MODULE),
    Global = ?config(global),
    AuthenticatorConfig1 = #{<<"mechanism">> => <<"password-based">>,
                             <<"backend">> => <<"built-in-database">>,
                             <<"enable">> => true},
    AuthenticatorConfig2 = #{<<"mechanism">> => <<"password-based">>,
                             <<"backend">> => <<"mysql">>,
                             <<"enable">> => true},
    ID1 = <<"password-based:built-in-database">>,
    ID2 = <<"password-based:mysql">>,

    ?assertMatch({ok, []}, ?AUTHN:list_chains()),

    ?assertMatch(
       {ok, _},
       update_config([authentication], {create_authenticator, Global, AuthenticatorConfig1})),

    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 1}}},
       ?AUTHN:lookup_authenticator(Global, ID1)),

    ?assertMatch(
       {ok, _},
       update_config([authentication], {create_authenticator, Global, AuthenticatorConfig2})),

    ?assertMatch(
       {ok, #{id := ID2, state := #{mark := 1}}},
       ?AUTHN:lookup_authenticator(Global, ID2)),

    ?assertMatch(
       {ok, _},
       update_config([authentication],
                     {update_authenticator,
                      Global,
                      ID1,
                      AuthenticatorConfig1#{<<"enable">> => false}
                     })),

    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 2}}},
       ?AUTHN:lookup_authenticator(Global, ID1)),

    ?assertMatch(
       {ok, _},
       update_config([authentication], {move_authenticator, Global, ID2, top})),

    ?assertMatch({ok, [#{id := ID2}, #{id := ID1}]}, ?AUTHN:list_authenticators(Global)),

    ?assertMatch({ok, _}, update_config([authentication], {delete_authenticator, Global, ID1})),
    ?assertEqual(
       {error, {not_found, {authenticator, ID1}}},
       ?AUTHN:lookup_authenticator(Global, ID1)),

    ?assertMatch(
       {ok, _},
       update_config([authentication], {delete_authenticator, Global, ID2})),

    ?assertEqual(
       {error, {not_found, {authenticator, ID2}}},
       ?AUTHN:lookup_authenticator(Global, ID2)),

    ListenerID = 'tcp:default',
    ConfKeyPath = [listeners, tcp, default, authentication],

    ?assertMatch(
       {ok, _},
       update_config(ConfKeyPath,
                     {create_authenticator, ListenerID, AuthenticatorConfig1})),

    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 1}}},
       ?AUTHN:lookup_authenticator(ListenerID, ID1)),

    ?assertMatch(
       {ok, _},
       update_config(ConfKeyPath,
                     {create_authenticator, ListenerID, AuthenticatorConfig2})),

    ?assertMatch(
       {ok, #{id := ID2, state := #{mark := 1}}},
       ?AUTHN:lookup_authenticator(ListenerID, ID2)),

    ?assertMatch(
       {ok, _},
       update_config(ConfKeyPath,
                     {update_authenticator,
                      ListenerID,
                      ID1,
                      AuthenticatorConfig1#{<<"enable">> => false}
                     })),

    ?assertMatch(
       {ok, #{id := ID1, state := #{mark := 2}}},
       ?AUTHN:lookup_authenticator(ListenerID, ID1)),

    ?assertMatch(
       {ok, _},
       update_config(ConfKeyPath, {move_authenticator, ListenerID, ID2, top})),

    ?assertMatch(
       {ok, [#{id := ID2}, #{id := ID1}]},
       ?AUTHN:list_authenticators(ListenerID)),

    ?assertMatch(
       {ok, _},
       update_config(ConfKeyPath, {delete_authenticator, ListenerID, ID1})),

    ?assertEqual(
       {error, {not_found, {authenticator, ID1}}},
       ?AUTHN:lookup_authenticator(ListenerID, ID1));

t_update_config({'end', Config}) ->
    ?AUTHN:delete_chain(?config(global)),
    ?AUTHN:deregister_providers([?config("auth1"), ?config("auth2")]),
    ok.


t_restart({'init', Config}) -> Config;

t_restart(Config) when is_list(Config) ->
    ?assertEqual({ok, []}, ?AUTHN:list_chain_names()),

    ?AUTHN:create_chain(test_chain),
    ?assertEqual({ok, [test_chain]}, ?AUTHN:list_chain_names()),

    ok = supervisor:terminate_child(emqx_authentication_sup, ?AUTHN),
    {ok, _} = supervisor:restart_child(emqx_authentication_sup, ?AUTHN),

    ?assertEqual({ok, [test_chain]}, ?AUTHN:list_chain_names());

t_restart({'end', _Config}) ->
    ?AUTHN:delete_chain(test_chain),
    ok.


t_convert_certs({_, Config}) -> Config;

t_convert_certs(Config) when is_list(Config) ->
    Global = <<"mqtt:global">>,
    Certs = certs([ {<<"keyfile">>, "key.pem"}
                  , {<<"certfile">>, "cert.pem"}
                  , {<<"cacertfile">>, "cacert.pem"}
                  ]),

    CertsDir = certs_dir(Config, [Global, <<"password-based:built-in-database">>]),
    #{<<"ssl">> := NCerts} = convert_certs(CertsDir, #{<<"ssl">> => Certs}),

    Certs2 = certs([ {<<"keyfile">>, "key.pem"}
                   , {<<"certfile">>, "cert.pem"}
                   ]),

    #{<<"ssl">> := NCerts2} = convert_certs(
                                CertsDir,
                                #{<<"ssl">> => Certs2}, #{<<"ssl">> => NCerts}),

    ?assertEqual(maps:get(<<"keyfile">>, NCerts), maps:get(<<"keyfile">>, NCerts2)),
    ?assertEqual(maps:get(<<"certfile">>, NCerts), maps:get(<<"certfile">>, NCerts2)),

    Certs3 = certs([ {<<"keyfile">>, "client-key.pem"}
                   , {<<"certfile">>, "client-cert.pem"}
                   , {<<"cacertfile">>, "cacert.pem"}
                   ]),

    #{<<"ssl">> := NCerts3} = convert_certs(
                                CertsDir,
                                #{<<"ssl">> => Certs3}, #{<<"ssl">> => NCerts2}),

    ?assertNotEqual(maps:get(<<"keyfile">>, NCerts2), maps:get(<<"keyfile">>, NCerts3)),
    ?assertNotEqual(maps:get(<<"certfile">>, NCerts2), maps:get(<<"certfile">>, NCerts3)),

    ?assertEqual(true, filelib:is_regular(maps:get(<<"keyfile">>, NCerts3))),
    clear_certs(CertsDir, #{<<"ssl">> => NCerts3}),
    ?assertEqual(false, filelib:is_regular(maps:get(<<"keyfile">>, NCerts3))).

update_config(Path, ConfigRequest) ->
    emqx:update_config(Path, ConfigRequest, #{rawconf_with_defaults => true}).

certs(Certs) ->
    CertsPath = emqx_common_test_helpers:deps_path(emqx, "etc/certs"),
    lists:foldl(fun({Key, Filename}, Acc) ->
                    {ok, Bin} = file:read_file(filename:join([CertsPath, Filename])),
                    Acc#{Key => Bin}
                end, #{}, Certs).

register_provider(Type, Module) ->
    ok = ?AUTHN:register_providers([{Type, Module}]).

certs_dir(CtConfig, Path) ->
    DataDir = proplists:get_value(data_dir, CtConfig),
    Dir = filename:join([DataDir | Path]),
    filelib:ensure_dir(Dir),
    Dir.

convert_certs(CertsDir, SslConfig) ->
    emqx_authentication_config:convert_certs(CertsDir, SslConfig).

convert_certs(CertsDir, New, Old) ->
    emqx_authentication_config:convert_certs(CertsDir, New, Old).

clear_certs(CertsDir, SslConfig) ->
    emqx_authentication_config:clear_certs(CertsDir, SslConfig).
