%% @copyright Geoff Cant
%% @author Geoff Cant <nem@erlang.geek.nz>
%% @version {@vsn}, {@date} {@time}
%% @doc Run lockstep callback from json dump file for testing.
%% @end
-module(file_lockstep).

%% Public API.
-export([run/2]).

%% for timer:tc
-export([foreach_line/3]).

run(Mod, File) ->
    {ok, F} = file:open(File, [binary, read_ahead, raw]),
    try
        {ok, _, MState} = cb_init(Mod),
        case timer:tc(?MODULE, foreach_line, [{Mod, MState}, F, 0]) of
            {Time, {ok, State, Count}} ->
                {ok, [{state, State},
                      {records, Count},
                      {total, Time},
                      {time_per_record, Time / Count}]};
            Else ->
                {error, Else}
        end
    after
        file:close(F)
    end.

cb_init(Mod) ->
    Mod:init([]).

foreach_line(MS, F, Cnt) ->
    foreach_line(MS, F, file:read_line(F), Cnt).

foreach_line({Callback, CbState}, F, {ok, Line}, Cnt) ->
    case catch mochijson2:decode(Line) of
        {struct, Props} ->
            case catch Callback:handle_msg(Props, CbState) of
                {noreply, CbState1} ->
                    NewMS = {Callback, CbState1},
                    foreach_line(NewMS, F, Cnt+1);
                {stop, Reason, CbState1} ->
                    {Reason, CbState1, Cnt};
                {'EXIT', Err} ->
                    {Err, CbState, Cnt}
            end
    end;
foreach_line(MS, _F, eof, Cnt) ->
    {ok, MS, Cnt}.
