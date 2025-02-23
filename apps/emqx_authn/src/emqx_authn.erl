%%--------------------------------------------------------------------
%% Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_authn).

-export([ providers/0
        , check_config/1
        , check_config/2
        , check_configs/1
        ]).

providers() ->
    [ {{'password-based', 'built-in-database'}, emqx_authn_mnesia}
    , {{'password-based', mysql}, emqx_authn_mysql}
    , {{'password-based', postgresql}, emqx_authn_pgsql}
    , {{'password-based', mongodb}, emqx_authn_mongodb}
    , {{'password-based', redis}, emqx_authn_redis}
    , {{'password-based', 'http'}, emqx_authn_http}
    , {jwt, emqx_authn_jwt}
    , {{scram, 'built-in-database'}, emqx_enhanced_authn_scram_mnesia}
    ].

check_configs(C) when is_map(C) ->
    check_configs([C]);
check_configs([]) -> [];
check_configs([Config | Configs]) ->
    [check_config(Config) | check_configs(Configs)].

check_config(Config) ->
    check_config(Config, #{}).

check_config(Config, Opts) ->
    case do_check_config(Config, Opts) of
        #{config := Checked} -> Checked;
        #{<<"config">> := WithDefaults} -> WithDefaults
    end.

do_check_config(#{<<"mechanism">> := Mec} = Config, Opts) ->
    Key = case maps:get(<<"backend">>, Config, false) of
              false -> atom(Mec);
              Backend -> {atom(Mec), atom(Backend)}
          end,
    case lists:keyfind(Key, 1, providers()) of
        false ->
            throw({unknown_handler, Key});
        {_, Provider} ->
            hocon_schema:check_plain(Provider, #{<<"config">> => Config},
                                     Opts#{atom_key => true})
    end.

atom(Bin) ->
    binary_to_existing_atom(Bin, utf8).
