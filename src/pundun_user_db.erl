%%%===================================================================
%% @author Erdem Aksu
%% @copyright 2015 Pundun Labs AB
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or 
%% implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% -------------------------------------------------------------------
%% @title
%% @doc
%% Module Description:
%% @end
%%%===================================================================

-module(pundun_user_db).

-export([create_tables/1,
	 add_user/2,
	 del_user/1,
	 passwd/2,
	 list_users/0]).

-export([transaction/1]).

-include("pundun.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Create tables on given Nodes.
%% @end
%%--------------------------------------------------------------------
-spec create_tables(Nodes :: [node()]) -> ok | {error, Reason :: any()}.
create_tables(Nodes) ->
    [create_table(Nodes, T) || T <- [pundun_user]].

%%--------------------------------------------------------------------
%% @doc
%% Run mnesia activity with access context transaction with given fun
%% @end
%%--------------------------------------------------------------------
-spec transaction(Fun :: fun()) ->
    {aborted, Reason :: term()} | {atomic, ResultOfFun :: term()}.
transaction(Fun) ->
    case catch mnesia:activity(transaction, Fun) of
	{'EXIT', Reason} ->
	    {error, Reason};
	Result ->
	    {atomic, Result}
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec create_table(Nodes::[node()], Name::atom()) -> ok | {error, Reason::term()}.
create_table(Nodes, Name) when Name == pundun_user ->
    TabDef = [{access_mode, read_write},
	      {attributes, record_info(fields, pundun_user)},
	      {disc_copies, Nodes},
	      {load_order, 39},
	      {record_name, Name},
	      {type, set}
	     ],
    mnesia:create_table(Name, TabDef),
    ok = write_admin_user();
create_table(_, _) ->
    {error, "Unknown table definition"}.

-spec add_user(User :: string(), PassWd :: string()) ->
    {ok, User :: string()} | {error, Reason :: term()}.
add_user(User, PassWd) ->
    case transaction(fun()-> add_user_fun(User, PassWd) end) of
	{atomic, {ok, U}} ->
	    {ok, U};
	{atomic, Else} ->
	    Else;
	{error, Reason} ->
	    {error, Reason}
    end.

-spec add_user_fun(User :: string(), PassWd :: string()) ->
    {ok, User :: string()} | {error, Reason :: term()}.
add_user_fun(User, PassWd) ->
    User_ = stringprep:prepare(User),
    case mnesia:read(pundun_user, User_) of
	[] ->
	    PassWd_ = stringprep:prepare(PassWd),
	    Salt = [crypto:rand_uniform(48,125) || _ <- lists:seq(0,15)],
	    IterCount = 4096,
	    SaltedPassword = scramerl_lib:hi(PassWd_, Salt, IterCount),
	    Record = #pundun_user{username = User_,
				  salt = Salt,
				  iteration_count = IterCount,
				  salted_password = SaltedPassword},
	    ok = mnesia:write(Record),
	    {ok, User_};
	[_] ->
	    {error, user_exists};
	Else ->
	    Else
    end.

-spec del_user(User :: string()) ->
    ok | {error, Reason :: term()}.
del_user(User) ->
    User_ = stringprep:prepare(User),
    case transaction(fun() -> mnesia:delete(pundun_user, User_, write) end) of
	{atomic, ok} -> ok;
	Else -> Else
    end.

-spec passwd(User :: string(), Passwd :: string()) ->
    ok | {error, Reason :: term()}.
passwd(User, PassWd) ->
    case transaction(fun()-> passwd_fun(User, PassWd) end) of
	{atomic, {ok, U}} ->
	    {ok, U};
	{atomic, Else} ->
	    Else;
	{error, Reason} ->
	    {error, Reason}
    end.

-spec passwd_fun(User :: string(), PassWd :: string()) ->
    {ok, User :: string()} | {error, Reason :: term()}.
passwd_fun(User, PassWd) ->
    User_ = stringprep:prepare(User),
    case mnesia:read(pundun_user, User_) of
	[R] ->
	    PassWd_ = stringprep:prepare(PassWd),
	    Salt = [crypto:rand_uniform(48,125) || _ <- lists:seq(0,15)],
	    IterCount = R#pundun_user.iteration_count,
	    SaltedPassword = scramerl_lib:hi(PassWd_, Salt, IterCount),
	    Record = R#pundun_user{salt = Salt,
				   salted_password = SaltedPassword},
	    mnesia:write(Record);
	[] ->
	    {error, user_not_exists};
	Else ->
	    Else
    end.

-spec list_users() ->
    [string()].
list_users()->
    mnesia:dirty_all_keys(pundun_user).

-spec write_admin_user() -> ok.
write_admin_user() ->
    Salt = [crypto:rand_uniform(48,125) || _ <- lists:seq(0,15)],
    Normalized = stringprep:prepare("admin"),
    IterCount = 4096,
    SaltedPassword = scramerl_lib:hi(Normalized, Salt, IterCount),
    Record = #pundun_user{username = "admin",
			  salt = Salt,
			  iteration_count = IterCount,
			  salted_password = SaltedPassword},
    Fun = fun() -> mnesia:write(Record) end,
    {atomic, ok} = transaction(Fun),
    ok.
