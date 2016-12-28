%%%-------------------------------------------------------------------
%%% @author regikul
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Dec 2016 14:22
%%%-------------------------------------------------------------------
-module(sctp_cli_client).
-author("regikul").

-behaviour(gen_server).

%% API
-export([
  start_link/0,
  connect/2,
  write/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-include_lib("kernel/include/inet_sctp.hrl").

-record(state, {
  socket :: gen_sctp:sctp_socket(),
  assocs = [] :: [#sctp_assoc_change{}]
}).

%%%===================================================================
%%% API
%%%===================================================================

-spec connect(string(), pos_integer()) -> ok.
connect(Host, Port) ->
  gen_server:cast(?SERVER, {connect, Host, Port}).

-spec write(term()) -> ok.
write(Data) ->
  gen_server:cast(?SERVER, {write, Data}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  {ok, Socket} = gen_sctp:open(),
  gen_server:cast(self(), recv),
  {ok, #state{socket = Socket}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({'connect', Host, Port}, #state{socket = Socket,
                                            assocs = Assocs
                                           } = State) ->
  NewState = case gen_sctp:connect(Socket, Host, Port, [], 1000) of
               {ok, Assoc} ->
                 lager:info("connected! Association: ~p", [Assoc]),
                 State#state{assocs = [Assoc | Assocs]};
               {error, _Reason} ->
                 lager:error("can't connect due to ~p", [_Reason]),
                 State
             end,
  {noreply, NewState};
handle_cast(recv, #state{socket = Socket} = State) ->
  case gen_sctp:recv(Socket, 500) of
    {ok, {FromIP, FromPort, AncData, Data}} ->
      lager:info("receive from ~p:~p bunch of data: ~p", [FromIP, FromPort, Data]),
      lager:info("ancillary data: ~p", [AncData]);
    {error, timeout} -> ok;
    {error, _Reason} ->
      lager:error("can not read due to: ~p", [_Reason])
  end,
  gen_server:cast(self(), recv),
  {noreply, State};
handle_cast({write, Data}, #state{assocs = [Assoc | Assocs],
                                  socket = Socket
                                 } = State) ->
  case gen_sctp:send(Socket, Assoc, 0, term_to_binary(Data)) of
    ok -> ok;
    {error, _Reason} -> lager:error("cant send data (~p) due to ~p", [Data, _Reason])
  end,
  {noreply, State#state{assocs = Assocs ++ [Assoc]}};
handle_cast(_Request, State) ->
  lager:info("unknown cast: ~p", [_Request]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
