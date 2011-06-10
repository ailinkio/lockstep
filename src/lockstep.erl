
-module(lockstep).
-author("Orion Henry <orion@heroku.com>").
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([start/2, start/3, start_link/2, start_link/3, ets/1 ]).

-record(state, { socket, ets, dets, host, port, path, digest, transfer, contentlength, writes=0 }).

start(Url, Digest) -> start(Url, Digest, null).

start(Url, Digest, Dets) -> gen_server:start(?MODULE, [Url, Digest, Dets], []).

start_link(Url, Digest) -> start_link(Url, Digest, null).

start_link(Url, Digest, Dets) -> gen_server:start_link(?MODULE, [Url, Digest, Dets], []).

ets(Pid) -> gen_server:call(Pid,ets).

%% handle URL path that does not end in '/'
%% handle redirects

init([Uri, Digest, DetsFile]) when is_list(Uri) and is_function(Digest) ->
  {http,[],Host, Port, Path, []} = http_uri:parse(Uri),
  { Ets, Dets } = setup_tables(DetsFile),
  erlang:send(self(), connect),
  erlang:send_after(10000, self(), stats),
  { ok, #state{ets=Ets, dets=Dets, host=Host, port=Port, path=Path, digest=Digest } }.

handle_call(ets, _From, State) ->
    {reply, State#state.ets, State};
handle_call(_Message, _From, State) ->
    {reply, error, State}.

handle_cast(_Message, State) ->
  {noreply, State}.

handle_info({http, Sock, Http}, State) ->
  State2 = case Http of
    { http_response, {1,1}, 200, <<"OK">> } ->
      State;
    { http_header, _, _Key = 'Content-Length', _,  Size } ->
      io:format("Header: ~p: ~p~n",[_Key, Size]),
      State#state{ contentlength=list_to_integer(binary_to_list(Size)) };
    { http_header, _, _Key = 'Transfer-Encoding', _,  _Value = <<"chunked">> } ->
      io:format("Header: ~p: ~p~n",[_Key, _Value]),
      State#state{ transfer=chunked };
    { http_header, _, _Key, _, _Value } ->
      io:format("Header: ~p: ~p~n",[_Key, _Value]),
      State;
    http_eoh ->
      inet:setopts(Sock, [{packet, line}]),
      State
  end,
  inet:setopts(Sock, [{active, once}]),
  {noreply, State2};
handle_info({tcp, _Sock, <<"0\r\n">> }, #state{transfer=chunked}=State) ->
  {noreply, disconnect(State) };
handle_info({tcp, Sock, Line}, #state{writes=Writes, transfer=chunked}=State) ->
  Size = read_chunk_size(Line),
  State2 = read_chunk(Sock, Size, State),
  {noreply, State2#state{writes=Writes+1}};
handle_info({tcp, Sock, Line}, #state{writes=Writes}=State) ->
  Size = size(Line),
  Remaining = State#state.contentlength - Size,
  State2 = process_chunk(Line, State),
  case Remaining < 1 of
    true ->
      {noreply, disconnect(State2#state{writes=Writes+1}) };
    false ->
      inet:setopts(Sock, [{active, once}, { packet, line }]),
      {noreply, State2#state{contentlength=Remaining, writes=Writes+1}}
  end;
handle_info({tcp_closed, _Sock}, State) ->
  {noreply, connect(State)};
handle_info(connect, State) ->
  {noreply, connect(State)};
handle_info(stats, State) ->
  io:format("Stats: ~p writes/sec~n",[State#state.writes/10]),
  erlang:send_after(10000, self(), stats),
  {noreply, State#state{writes=0}};
handle_info(Message, State) ->
  io:format("unhandled info: ~p~n", Message),
  {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVersion, State, _Extra) -> {ok, State}.

read_chunk_size(Line) ->
  { ok, [Bytes], [] } = io_lib:fread("~16u\r\n", binary_to_list(Line)),
  Bytes.

read_chunk(Socket, Bytes, State) ->
  inet:setopts(Socket, [{active, false}, { packet, raw }]),
  case gen_tcp:recv(Socket, Bytes + 2) of
    { ok, <<Data:Bytes/binary,"\r\n">> } ->
      inet:setopts(Socket, [{active, once}, { packet, line }]),
      process_chunk(Data, State);
    _ ->
      disconnect(State)
  end.

process_chunk(Chunk, State) ->
  case mochijson2:decode(Chunk) of
    { struct, Props } -> analyze(Props, State)
  end,
  State.

analyze(Props, State) ->
  { ok, Action, Time } = analyze(Props, set, 0),
  case Action of
    set -> set(Time, (State#state.digest)(Props), State);
    delete -> delete(Time, (State#state.digest)(Props), State)
  end.

analyze([{<<"deleted_at">>, Time} | Props], _Action, _Time) when is_integer(Time) ->
  analyze(Props, delete, Time);
analyze([{<<"updated_at">>, Time} | Props], Action, _Time) when is_integer(Time) ->
  analyze(Props, Action, Time);
analyze([ _ | Props], Action, Time) ->
  analyze(Props, Action, Time);
analyze([], Action, Time) ->
  { ok, Action, Time }.

head(State) ->
  case ets:lookup(State#state.ets, lockstep_head) of
    [{ lockstep_head, Time }] -> Time - 1; %% 1 second before
    _ -> 0
  end.

set(Time, Record, State) ->
%  io:format("SET ~p ~p~n",[Time, Record]),
  ets:insert(State#state.ets, Record),
  ets:insert(State#state.ets, { lockstep_head, Time }),
  set_dets(Time, Record, State#state.dets).

set_dets(_Time, _Record, null) -> ok;
set_dets(Time, Record, Dets) ->
  dets:insert(Dets, Record),
  dets:insert(Dets, { lockstep_head, Time }).

delete(Time, Record, State) ->
%  io:format("DEL ~p ~p~n",[Time, Record]),
  ets:delete(State#state.ets, Record),
  ets:insert(State#state.ets, { lockstep_head, Time }),
  delete_dets(Time, Record, State#state.dets).

delete_dets(_Time, _Record, null) -> ok;
delete_dets(Time, Record, Dets) ->
  dets:delete(Dets, Record),
  dets:insert(Dets, { lockstep_head, Time }).

setup_tables(null) ->
  { ets:new(?MODULE, [ set, protected, { read_concurrency, true } ]), null };
setup_tables(Filename) ->
  Ets = ets:new(?MODULE, [ set, protected, { read_concurrency, true } ]),
  {ok, Dets} = dets:open_file(Filename, []),
  Ets = dets:to_ets(Dets, Ets),
  { Ets, Dets }.

disconnect(State) ->
  io:format("closing connection~n"),
  gen_tcp:close(State#state.socket),
  erlang:send_after(3000, self(), connect),
  State#state{socket=null}.

connect(State) ->
  Opts = [binary, {packet, http_bin}, {packet_size, 1024 * 1024}, {recbuf, 1024 * 1024}, {active, once}],
  io:format("Connecting to http://~s:~p~s~p...",[ State#state.host, State#state.port, State#state.path, head(State) ]),
  case gen_tcp:connect( State#state.host, State#state.port, Opts, 10000) of
    {ok, Sock} ->
      io:format("ok~n"),
      gen_tcp:send(Sock, [ <<"GET ">> , State#state.path, integer_to_list(head(State)), <<" HTTP/1.1\r\nHost: ">>, State#state.host ,<<"\r\n\r\n">> ]),
      State#state{socket=Sock, transfer=null};
    {error, Error } ->
      io:format("error/~p~n",[Error]),
      erlang:send_after(3000, self(), connect),
      State#state{socket=null}
  end.

