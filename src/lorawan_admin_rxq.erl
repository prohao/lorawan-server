%
% Copyright (c) 2016 Petr Gotthard <petr.gotthard@centrum.cz>
% All rights reserved.
% Distributed under the terms of the MIT License. See the LICENSE file.
%
-module(lorawan_admin_rxq).

-export([init/2]).
-export([is_authorized/2]).
-export([allowed_methods/2]).
-export([content_types_provided/2]).
-export([resource_exists/2]).

-export([get_rxframe/2]).

-include("lorawan.hrl").

init(Req, Opts) ->
    {cowboy_rest, Req, Opts}.

is_authorized(Req, State) ->
    lorawan_admin:handle_authorization(Req, State).

allowed_methods(Req, State) ->
    {[<<"OPTIONS">>, <<"GET">>], Req, State}.

content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, get_rxframe}
    ], Req, State}.

get_rxframe(Req, State) ->
    DevAddr = cowboy_req:binding(devaddr, Req),
    {ActRec, _} = lorawan_db:get_rxframes(lorawan_mac:hex_to_binary(DevAddr)),
    % construct Google Chart DataTable
    % see https://developers.google.com/chart/interactive/docs/reference#dataparam
    Array = [{cols, [
                [{id, <<"fcnt">>}, {label, <<"FCnt">>}, {type, <<"number">>}],
                [{id, <<"rssi">>}, {label, <<"RSSI (dBm)">>}, {type, <<"number">>}],
                [{id, <<"snr">>}, {label, <<"SNR (dB)">>}, {type, <<"number">>}]
                ]},
            {rows, lists:map(fun(#rxframe{fcnt=FCnt, rssi=RSSI, lsnr=SNR}) ->
                    [{c, [
                        [{v, FCnt}],
                        [{v, RSSI}],
                        [{v, SNR}]
                    ]}]
                end, ActRec)
            }
        ],
    {jsx:encode([{devaddr, DevAddr}, {array, Array}]), Req, State}.

resource_exists(Req, State) ->
    case mnesia:dirty_index_read(rxframes,
            lorawan_mac:hex_to_binary(cowboy_req:binding(devaddr, Req)), #rxframe.devaddr) of
        [] -> {false, Req, State};
        [_First|_Rest] -> {true, Req, State}
    end.

% end of file
