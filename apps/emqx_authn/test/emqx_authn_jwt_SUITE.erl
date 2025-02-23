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

-module(emqx_authn_jwt_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

% -include_lib("common_test/include/ct.hrl").
% -include_lib("eunit/include/eunit.hrl").

% -include("emqx_authn.hrl").

% -define(AUTH, emqx_authn).

all() ->
    emqx_common_test_helpers:all(?MODULE).

% init_per_suite(Config) ->
%     emqx_common_test_helpers:start_apps([emqx_authn]),
%     Config.

% end_per_suite(_) ->
%     emqx_common_test_helpers:stop_apps([emqx_authn]),
%     ok.

% t_jwt_authenticator(_) ->
%     AuthenticatorName = <<"myauthenticator">>,
%     Config = #{name => AuthenticatorName,
%                mechanism => jwt,
%                use_jwks => false,
%                algorithm => 'hmac-based',
%                secret => <<"abcdef">>,
%                secret_base64_encoded => false,
%                verify_claims => []},
%     {ok, #{name := AuthenticatorName, id := ID}} = ?AUTH:create_authenticator(?CHAIN, Config),

%     Payload = #{<<"username">> => <<"myuser">>},
%     JWS = generate_jws('hmac-based', Payload, <<"abcdef">>),
%     ClientInfo = #{username => <<"myuser">>,
% 			       password => JWS},
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo, ignored)),

%     Payload1 = #{<<"username">> => <<"myuser">>, <<"is_superuser">> => true},
%     JWS1 = generate_jws('hmac-based', Payload1, <<"abcdef">>),
%     ClientInfo1 = #{username => <<"myuser">>,
% 			        password => JWS1},
%     ?assertEqual({stop, {ok, #{is_superuser => true}}}, ?AUTH:authenticate(ClientInfo1, ignored)),

%     BadJWS = generate_jws('hmac-based', Payload, <<"bad_secret">>),
%     ClientInfo2 = ClientInfo#{password => BadJWS},
%     ?assertEqual({stop, {error, not_authorized}}, ?AUTH:authenticate(ClientInfo2, ignored)),

%     %% secret_base64_encoded
%     Config2 = Config#{secret => base64:encode(<<"abcdef">>),
%                       secret_base64_encoded => true},
%     ?assertMatch({ok, _}, ?AUTH:update_authenticator(?CHAIN, ID, Config2)),
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo, ignored)),

%     Config3 = Config#{verify_claims => [{<<"username">>, <<"${mqtt-username}">>}]},
%     ?assertMatch({ok, _}, ?AUTH:update_authenticator(?CHAIN, ID, Config3)),
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo, ignored)),
%     ?assertEqual({stop, {error, bad_username_or_password}}, ?AUTH:authenticate(ClientInfo#{username => <<"otheruser">>}, ok)),

%     %% Expiration
%     Payload3 = #{ <<"username">> => <<"myuser">>
%                 , <<"exp">> => erlang:system_time(second) - 60},
%     JWS3 = generate_jws('hmac-based', Payload3, <<"abcdef">>),
%     ClientInfo3 = ClientInfo#{password => JWS3},
%     ?assertEqual({stop, {error, bad_username_or_password}}, ?AUTH:authenticate(ClientInfo3, ignored)),

%     Payload4 = #{ <<"username">> => <<"myuser">>
%                 , <<"exp">> => erlang:system_time(second) + 60},
%     JWS4 = generate_jws('hmac-based', Payload4, <<"abcdef">>),
%     ClientInfo4 = ClientInfo#{password => JWS4},
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo4, ignored)),

%     %% Issued At
%     Payload5 = #{ <<"username">> => <<"myuser">>
%                 , <<"iat">> => erlang:system_time(second) - 60},
%     JWS5 = generate_jws('hmac-based', Payload5, <<"abcdef">>),
%     ClientInfo5 = ClientInfo#{password => JWS5},
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo5, ignored)),

%     Payload6 = #{ <<"username">> => <<"myuser">>
%                 , <<"iat">> => erlang:system_time(second) + 60},
%     JWS6 = generate_jws('hmac-based', Payload6, <<"abcdef">>),
%     ClientInfo6 = ClientInfo#{password => JWS6},
%     ?assertEqual({stop, {error, bad_username_or_password}}, ?AUTH:authenticate(ClientInfo6, ignored)),

%     %% Not Before
%     Payload7 = #{ <<"username">> => <<"myuser">>
%                 , <<"nbf">> => erlang:system_time(second) - 60},
%     JWS7 = generate_jws('hmac-based', Payload7, <<"abcdef">>),
%     ClientInfo7 = ClientInfo#{password => JWS7},
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo7, ignored)),

%     Payload8 = #{ <<"username">> => <<"myuser">>
%                 , <<"nbf">> => erlang:system_time(second) + 60},
%     JWS8 = generate_jws('hmac-based', Payload8, <<"abcdef">>),
%     ClientInfo8 = ClientInfo#{password => JWS8},
%     ?assertEqual({stop, {error, bad_username_or_password}}, ?AUTH:authenticate(ClientInfo8, ignored)),

%     ?assertEqual(ok, ?AUTH:delete_authenticator(?CHAIN, ID)),
%     ok.

% t_jwt_authenticator2(_) ->
%     Dir = code:lib_dir(emqx_authn, test),
%     PublicKey = list_to_binary(filename:join([Dir, "data/public_key.pem"])),
%     PrivateKey = list_to_binary(filename:join([Dir, "data/private_key.pem"])),
%     AuthenticatorName = <<"myauthenticator">>,
%     Config = #{name => AuthenticatorName,
%                mechanism => jwt,
%                use_jwks => false,
%                algorithm => 'public-key',
%                certificate => PublicKey,
%                verify_claims => []},
%     {ok, #{name := AuthenticatorName, id := ID}} = ?AUTH:create_authenticator(?CHAIN, Config),

%     Payload = #{<<"username">> => <<"myuser">>},
%     JWS = generate_jws('public-key', Payload, PrivateKey),
%     ClientInfo = #{username => <<"myuser">>,
% 			       password => JWS},
%     ?assertEqual({stop, {ok, #{is_superuser => false}}}, ?AUTH:authenticate(ClientInfo, ignored)),
%     ?assertEqual({stop, {error, not_authorized}}, ?AUTH:authenticate(ClientInfo#{password => <<"badpassword">>}, ignored)),

%     ?assertEqual(ok, ?AUTH:delete_authenticator(?CHAIN, ID)),
%     ok.

% generate_jws('hmac-based', Payload, Secret) ->
%     JWK = jose_jwk:from_oct(Secret),
%     Header = #{ <<"alg">> => <<"HS256">>
%               , <<"typ">> => <<"JWT">>
%               },
%     Signed = jose_jwt:sign(JWK, Header, Payload),
%     {_, JWS} = jose_jws:compact(Signed),
%     JWS;
% generate_jws('public-key', Payload, PrivateKey) ->
%     JWK = jose_jwk:from_pem_file(PrivateKey),
%     Header = #{ <<"alg">> => <<"RS256">>
%               , <<"typ">> => <<"JWT">>
%               },
%     Signed = jose_jwt:sign(JWK, Header, Payload),
%     {_, JWS} = jose_jws:compact(Signed),
%     JWS.
