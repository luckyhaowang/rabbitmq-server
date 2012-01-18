%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Console.
%%
%%   The Initial Developers of the Original Code are Rabbit Technologies Ltd.
%%
%%   Copyright (C) 2011 Rabbit Technologies Ltd.
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): ______________________________________.
%%
-module(rabbit_stomp_amqqueue_test).
-export([all_tests/0]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stomp_frame.hrl").

-define(QUEUE, <<"TestQueue">>).
-define(DESTINATION, "/amq/queue/TestQueue").

all_tests() ->
    [ok = run_test(TestFun) || TestFun <- [fun test_subscribe_error/2,
                                           fun test_subscribe/2,
                                           fun test_send/2]],
    ok.

run_test(TestFun) ->
    {ok, Connection} = amqp_connection:start(#amqp_params_direct{}),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    {ok, Sock} = rabbit_stomp_client:connect(),

    Result = (catch TestFun(Channel, Sock)),

    rabbit_stomp_client:disconnect(Sock),
    amqp_channel:close(Channel),
    amqp_connection:close(Connection),
    Result.

test_subscribe_error(_Channel, Sock) ->
    %% SUBSCRIBE to missing queue
    rabbit_stomp_client:send(
      Sock, "SUBSCRIBE", [{"destination", ?DESTINATION}]),
    #stomp_frame{command = "ERROR",
                 headers = Hdrs} = rabbit_stomp_client:recv(Sock),
    "not_found" = proplists:get_value("message", Hdrs),
    ok.

test_subscribe(Channel, Sock) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = ?QUEUE,
                                                    auto_delete = true}),

    %% subscribe and wait for receipt
    rabbit_stomp_client:send(Sock, "SUBSCRIBE", [{"destination", ?DESTINATION},
                                                 {"receipt", "foo"}]),
    #stomp_frame{command = "RECEIPT"} = rabbit_stomp_client:recv(Sock),

    %% send from amqp
    Method = #'basic.publish'{
      exchange    = <<"">>,
      routing_key = ?QUEUE},

    amqp_channel:call(Channel, Method, #amqp_msg{props = #'P_basic'{},
                                                 payload = <<"hello">>}),

    #stomp_frame{command     = "MESSAGE",
                 body_iolist = [<<"hello">>]} = rabbit_stomp_client:recv(Sock),

    ok.

test_send(Channel, Sock) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = ?QUEUE,
                                                    auto_delete = true}),

    %% subscribe and wait for receipt
    rabbit_stomp_client:send(
      Sock, "SUBSCRIBE", [{"destination", ?DESTINATION}, {"receipt", "foo"}]),
    #stomp_frame{command = "RECEIPT"} = rabbit_stomp_client:recv(Sock),

    %% send from stomp
    rabbit_stomp_client:send(
      Sock, "SEND", [{"destination", ?DESTINATION}], ["hello"]),

    #stomp_frame{command     = "MESSAGE",
                 body_iolist = [<<"hello">>]} = rabbit_stomp_client:recv(Sock),

    ok.
