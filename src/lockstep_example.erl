%% Copyright (c) 2011
%% Orion Henry <orion@heroku.com>
%% Jacob Vorreuter <jacob.vorreuter@gmail.com>
%%
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%%
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(lockstep_example).
-behaviour(gen_lockstep).

%% API
-export([start_link/2]).

%% gen_lockstep_server callbacks
-export([init/1, handle_msg/2, terminate/2]).

%%====================================================================
%% API functions
%%====================================================================
start_link(LockstepUrl, Opts) ->
    gen_lockstep:start_link(?MODULE, LockstepUrl, Opts).

%%====================================================================
%% gen_lockstep_server callbacks
%%====================================================================
init(_Opts) ->
    {ok, 0, undefined}.

handle_msg(Msg, State) ->
    io:format("msg: ~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    io:format("terminate: ~p~n", [_Reason]),
    ok.

