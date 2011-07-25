-module(game).

-behaviour(gen_fsm).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("tarabish_constants.hrl").
-include("tarabish_types.hrl").

-include_lib("eunit/include/eunit.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start/1, determine_dealer/2]).

%% gen_fsm callbacks
-export([init/1, state_name/2, state_name/3, handle_event/3,
	 handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% states:
-export([wait_trump/3, wait_card/3]).

%% from table:
-export([call_trump/3, play_card/3]).

-record(state, {table,
                hands,    % What the players are holding[[], [], [], []]
                score1,   % Score for player 0, 2
                score2,   % Score for player 1, 3
                deck,     % What's left of the deck
                dealer,   % Which seat is dealing
                trick,    % Trick number (for runs/done)
                order,    % The deal/play order for this hand
                inplay}). % Current cards on the table as [(Card, Seat),]

%% ====================================================================
%% External functions
%% ====================================================================
start(TablePid) ->
  gen_fsm:start(?MODULE, [TablePid], []).

call_trump(Game, Seat, Suit) ->
  gen_fsm:sync_send_event(Game, {call_trump, Seat, Suit}).

play_card(Game, Seat, Card) ->
  gen_fsm:sync_send_event(Game, {play_card, Seat, Card}).

%% ====================================================================
%% Server functions
%% ====================================================================
%% --------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}
%% --------------------------------------------------------------------
% TODO: monitor table
init([Table]) ->

  % TODO: use crypto:rand_bytes instead of random for shuffle
  % seed random number generator
  {A1,A2,A3} = now(),
  random:seed(A1, A2, A3),

  % in 0, 1, 2, 3
  Dealer = determine_dealer(Table, deck:shuffle(deck:new())),

  DealerEvent = #event{type=?tarabish_EventType_DEALER, seat=Dealer},
  table:broadcast(Table, DealerEvent),

  Deck = deck:shuffle(deck:new()),

  DealOrder = create_order(Dealer+1),

  State = #state{table=Table,
                 hands=[[], [], [], []],
                 score1=0,
                 score2=0,
                 deck=Deck,
                 dealer=Dealer,
                 order=DealOrder,
                 inplay=[],
                 trick=0},
  State1 = deal3(State),
  State2 = deal3(State1),

  AskTrumpEvent = #event{type=?tarabish_EventType_ASK_TRUMP,
                         seat=hd(DealOrder)},
  table:broadcast(Table, AskTrumpEvent),

  {ok, wait_trump, State2}.

% Handle force the dealer:
wait_trump({call_trump, Seat, ?tarabish_PASS}, _From,
    #state{order = [Seat|[]]} = State) ->
  {reply, {error, forced_to_call}, wait_trump, State};

% Other player passes
wait_trump({call_trump, Seat, ?tarabish_PASS = Suit}, _From,
    #state{order=[Seat|Rest]} = State) ->

  Event = #event{type=?tarabish_EventType_CALL_TRUMP, seat=Seat, suit=Suit},
  table:broadcast(State#state.table, Event),

  AskTrumpEvent = #event{type=?tarabish_EventType_ASK_TRUMP, seat=hd(Rest)},
  table:broadcast(State#state.table, AskTrumpEvent),

  {reply, ok, wait_trump, State#state{order=Rest}};

% Non pass:
wait_trump({call_trump, Seat, Suit}, _From,
    #state{order=[Seat|_Rest], dealer=Dealer} = State) ->

  Event = #event{type=?tarabish_EventType_CALL_TRUMP, seat=Seat, suit=Suit},
  table:broadcast(State#state.table, Event),
  State1 = deal3(State),

  PlayOrder = create_order(Dealer + 1),

  AskCardEvent = #event{type=?tarabish_EventType_ASK_CARD, seat=hd(PlayOrder)},
  table:broadcast(State#state.table, AskCardEvent),

  {reply, ok, wait_card, State1#state{order=PlayOrder, trick=1, inplay=[]}};

wait_trump(_Event, _From, State) ->
  {reply, {error, invalid}, wait_trump, State}.

% TODO: verify they can play that card:
wait_card({play_card, Seat, Card}, _From, #state{order=[Seat|Rest]} = State) ->

  Event = #event{type=?tarabish_EventType_PLAY_CARD, seat=Seat, card=Card},
  table:broadcast(State#state.table, Event),

  InPlay = [{Card, Seat}|State#state.inplay],

  case Rest =:= [] of
    true  ->
      {reply, ok, state_name, State}; % TODO: handle 4 cards in
    false ->
      Event1 = #event{type=?tarabish_EventType_ASK_CARD, seat=hd(Rest)},
      table:broadcast(State#state.table, Event1),

      {reply, ok, wait_card, State#state{order=Rest, inplay=InPlay}}
  end;

wait_card(_Event, _From, State) ->
  {reply, {error, invalid}, wait_card, State}.


%% --------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% --------------------------------------------------------------------
state_name(_Event, State) ->
    {next_state, state_name, State}.

%% --------------------------------------------------------------------
%% Func: StateName/3
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%% --------------------------------------------------------------------
state_name(_Event, _From, State) ->
    {reply, {error, bad_state}, state_name, State}.

%% --------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% --------------------------------------------------------------------
handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

%% --------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%% --------------------------------------------------------------------
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

%% --------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% --------------------------------------------------------------------
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

%% --------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%% --------------------------------------------------------------------
terminate(_Reason, _StateName, _StatData) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/4
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState, NewStateData}
%% --------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------
determine_dealer(Table, Deck) ->
  Dealer = determine_dealer(Table, Deck, [0,1,2,3]),
  Dealer.

determine_dealer(_Table, _Deck, [Player|[]]) ->
  Player;

determine_dealer(Table, Deck, Players) when is_list(Players) ->
  {Cards, Rest} = lists:split(length(Players), Deck),
  deal_one(Table, Deck, Players),
  HighCards = deck:high_card(Cards),
  % O(n^2) for n = 4
  PlayerMapper = fun(PlayerNum) -> lists:nth(PlayerNum + 1, Players) end,
  Players1 = lists:map(PlayerMapper, HighCards),
  determine_dealer(Table, Rest, Players1).

deal_one(_Table, Deck, []) ->
  Deck;
deal_one(Table, Deck, [_Player|Others]) ->
  [_Card|Rest] = Deck,
  %table:deal_one_up(Table, Player, Card),
  deal_one(Table, Rest, Others).

deal3_each(_Deck, Dealt, []) ->
  lists:reverse(Dealt);

deal3_each(Deck,  Dealt, [_Seat|Others]) ->
  {Cards, Deck1} = lists:split(3, Deck),
  deal3_each(Deck1, [Cards|Dealt], Others).

deal3(State) ->
  Order = create_order(State#state.dealer + 1),
  BeforeCards = State#state.hands,
  NewCards = deal3_each(State#state.deck, [], Order),
  Cards = lists:zipwith(fun lists:merge/2, BeforeCards, NewCards),

  table:deal3(State#state.table, State#state.dealer, NewCards),

  State#state{deck=lists:nthtail(12, State#state.deck),
              hands=Cards}.

create_order(First) when First > 3 ->
  create_order(First rem 4);

create_order(First) ->
  lists:seq(First, 3) ++ lists:seq(0, First - 1).

best_hand([{FirstCard, FirstSeat}|Rest], Trump) ->
  best_hand(Rest, {FirstCard, FirstSeat}, Trump, FirstCard#card.suit).

best_hand([], {_Card, Seat}, _Trump, _Led) ->
  Seat;

best_hand([{NewCard, NewSeat}|Rest], {Card, _Seat}, Trump, Led)
  when NewCard#card.suit == Trump, Card#card.suit /= Trump ->
    best_hand(Rest, {NewCard, NewSeat}, Trump, Led);

best_hand([{NewCard, _NewSeat}|Rest], {Card, Seat}, Trump, Led)
  when NewCard#card.suit /= Trump, Card#card.suit == Trump ->
    best_hand(Rest, {Card, Seat}, Trump, Led);

best_hand([{NewCard, NewSeat}|Rest], {Card, Seat}, Trump, Led)
  when NewCard#card.suit == Trump, Card#card.suit == Trump ->
    case deck:trump_higher(NewCard#card.value, Card#card.value) of
      true -> best_hand(Rest, {NewCard, NewSeat}, Trump, Led);
      false -> best_hand(Rest, {Card, Seat}, Trump, Led)
    end;

best_hand([{NewCard, _NewSeat}|Rest], {Card, Seat}, Trump, Led)
  when NewCard#card.suit /= Led ->
    best_hand(Rest, {Card, Seat}, Trump, Led);

best_hand([{NewCard, NewSeat}|Rest], {Card, Seat}, Trump, Led) ->
  case deck:nontrump_higher(NewCard#card.value, Card#card.value) of
    true -> best_hand(Rest, {NewCard, NewSeat}, Trump, Led);
    false -> best_hand(Rest, {Card, Seat}, Trump, Led)
  end.

%% --------------------------------------------------------------------
%%% Tests
%% --------------------------------------------------------------------

-define(J, #card{value=?tarabish_JACK}).
-define(N, #card{value=9}).
-define(A, #card{value=?tarabish_ACE}).
-define(T, #card{value=10}).
-define(E, #card{value=8}).

determine_dealer_test_() ->
  [
    ?_assertEqual(0, determine_dealer(self(), [?J, ?N, ?N, ?N])),
    ?_assertEqual(1, determine_dealer(self(), [?J, ?J, ?N, ?N, ?T, ?A])),
    ?_assertEqual(3, determine_dealer(self(), [?J, ?J, ?J, ?J,
                                               ?N, ?N, ?N, ?N,
                                               ?A, ?A, ?A, ?A,
                                               ?E, ?E, ?E, ?T]))
  ].

create_order_test_() ->
  [
    ?_assertEqual([0,1,2,3], create_order(0)),
    ?_assertEqual([1,2,3,0], create_order(1)),
    ?_assertEqual([2,3,0,1], create_order(2)),
    ?_assertEqual([3,0,1,2], create_order(3)),
    ?_assertEqual([0,1,2,3], create_order(4)),
    ?_assertEqual([1,2,3,0], create_order(5))
  ].

best_hand_test_() ->
  Hands1 = [{#card{value=8, suit=?tarabish_SPADES},   0},
            {#card{value=8, suit=?tarabish_DIAMONDS}, 1},
            {#card{value=8, suit=?tarabish_HEARTS},   2},
            {#card{value=8, suit=?tarabish_CLUBS},    3}],

  Hands2 = [{#card{value=8, suit=?tarabish_SPADES},   2},
            {#card{value=9, suit=?tarabish_SPADES},   3},
            {#card{value=6, suit=?tarabish_HEARTS},   0},
            {#card{value=6, suit=?tarabish_CLUBS},    1}],

  Hands3 = [{#card{value=8,  suit=?tarabish_SPADES},   3},
            {#card{value=8,  suit=?tarabish_DIAMONDS}, 0},
            {#card{value=9,  suit=?tarabish_DIAMONDS}, 1},
            {?J#card{suit=?tarabish_DIAMONDS}, 2}],

  [
    ?_assertEqual(0, best_hand(Hands1, ?tarabish_SPADES)),
    ?_assertEqual(2, best_hand(Hands1, ?tarabish_HEARTS)),
    ?_assertEqual(3, best_hand(Hands2, ?tarabish_DIAMONDS)),
    ?_assertEqual(2, best_hand(Hands3, ?tarabish_DIAMONDS))
  ].
