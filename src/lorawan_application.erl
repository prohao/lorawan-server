%
% Copyright (c) 2016 Petr Gotthard <petr.gotthard@centrum.cz>
% All rights reserved.
% Distributed under the terms of the MIT License. See the LICENSE file.
%
-module(lorawan_application).

-export([init/0, handle_join/3, handle_rx/5]).
-export([store_frame/3, send_stored_frames/2]).

-define(MAX_DELAY, 250). % milliseconds
-include("lorawan.hrl").

-callback init(App :: binary()) ->
    ok | {ok, [Path :: cowboy_router:route_path()]}.
-callback handle_join(DevAddr :: binary(), App :: binary(), AppID :: binary()) ->
    ok | {error, Error :: term()}.
-callback handle_rx(DevAddr :: binary(), App :: binary(), AppID :: binary(), Port :: integer(), Data :: binary()) ->
    ok | {send, Port :: integer(), Data :: binary()} |
    {error, Error :: term()}.

init() ->
    {ok, Modules} = application:get_env(plugins),
    do_init(Modules, []).

do_init([], Acc) -> {ok, Acc};
do_init([{App, Module}|Rest], Acc) ->
    case apply(Module, init, [App]) of
        ok -> do_init(Rest, Acc);
        {ok, Handlers} -> do_init(Rest, Acc++Handlers);
        Else -> Else
    end.

handle_join(DevAddr, App, AppID) ->
    % delete previously stored RX and TX frames
    lorawan_db:purge_rxframes(DevAddr),
    lorawan_db:purge_txframes(DevAddr),
    % callback
    invoke_handler(handle_join, App, [DevAddr, App, AppID]).

handle_rx(DevAddr, App, AppID, Port, Data) ->
    invoke_handler(handle_rx, App, [DevAddr, App, AppID, Port, Data]).

invoke_handler(Fun, App, Params) ->
    {ok, Modules} = application:get_env(plugins),
    case proplists:get_value(App, Modules) of
        undefined ->
            {error, {unknown_app, App}};
        Module ->
            apply(Module, Fun, Params)
    end.

store_frame(DevAddr, Port, Data) ->
    Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
    mnesia:transaction(fun() ->
        ok = mnesia:write(txframes, #txframe{frid= <<(erlang:system_time()):64>>, datetime=Now, devaddr=DevAddr, port=Port, data=Data}, write)
    end).

send_stored_frames(DevAddr, DefPort) ->
    case mnesia:dirty_select(txframes, [{#txframe{devaddr=DevAddr, _='_'}, [], ['$_']}]) of
        [] ->
            mnesia:subscribe({table, txframes, simple}),
            receive
                % the record name returned is 'txframes' regardless any record_name settings
                {mnesia_table_event, {write, TxFrame, _ActivityId}} when element(#txframe.devaddr, TxFrame) == DevAddr ->
                    transmit_and_delete(setelement(1, TxFrame, txframe), DefPort)
                after ?MAX_DELAY ->
                    ok
            end;
        [First|_Tail] ->
            transmit_and_delete(First, DefPort)
    end.

transmit_and_delete(TxFrame, DefPort) ->
    mnesia:dirty_delete(txframes, TxFrame#txframe.frid),
    % raw websocket does not define port
    OutPort = if
        TxFrame#txframe.port == undefined -> DefPort;
        true -> TxFrame#txframe.port
    end,
    {send, OutPort, TxFrame#txframe.data}.

% end of file
