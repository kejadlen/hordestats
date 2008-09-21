#!/usr/bin/env ruby

require 'camping'
require 'httparty'

Camping.goes :Hordestats

class Warfish
  include HTTParty
  base_uri 'http://warfish.net/war/services'
  format :xml

  def initialize(gid)
    Warfish.default_params :gid => gid
    @details = Warfish.get('/rest', :query => { :_method => 'warfish.tables.getDetails', :sections => 'map,continents' })
    @state = Warfish.get('/rest', :query => { :_method => 'warfish.tables.getState', :sections => 'players,board' })
  end

  def continents; @details['rsp']['continents']['continent']; end
  def map; @details['rsp']['map']['territory']; end
  def players; @state['rsp']['players']['player']; end
  def board; @state['rsp']['board']['area']; end
end

module Hordestats::Controllers
  class Index < R '/'
    def get; render :index; end

    def post
      gid = input['game'].scan(/\d+/)[0]
      redirect Game, gid
    end
  end

  class Game < R '/game/(\d+)'
    def get game_id
      @game_id = game_id
      warfish = Warfish.new(game_id)

      @players = warfish.players.inject({}) do |n,player|
        n[player['id']] = { :name => player['name'],
                            :total_units => 0,
                            :next_units => 5 }
        n
      end

      @country_names = warfish.map.inject({}) {|n,country| n[country['id']] = country['name']; n }

      @board = warfish.board.inject({}) do |n,country|
        n[country['id']] = country
        n[country['id']][:bonus_units] = 0
        n
      end

      @board.values.each do |country|
        @players[country['playerid']][:total_units] += country['units'].to_i
      end

      warfish.continents.each do |continent|
        country_ids = continent['cids'].split(',')
        player_ids = country_ids.map {|i| @board[i]['playerid'] }.uniq

        if player_ids.length == 1
          @players[player_ids[0]][:next_units] += 1
          country_ids.each {|i| @board[i][:bonus_units] += 1}
        end
      end

      render :stats
    end
  end
end

module Hordestats::Views
  def layout
    html do
      body do
        h1 { a 'HordeStats', :href => R(Index) }
        self << yield
      end
    end
  end

  def index
    p 'Please enter the URL of your game:'
    form :action => R(Index), :method => 'post' do
      input :name => 'game', :type => 'text'
      input :type => 'submit'
    end
  end

  def stats
    h2 { a 'View game on Warfish', :href => "http://warfish.net/war/play/game?gid=#{@game_id}" }

    h3 'Board State'

    script_array = []
    table do
      tr do
        th 'Player'
        th 'Total units'
        th 'Units next turn'
      end

      @players.each do |player_id, player|
        tr do
          td { a player[:name], :href => "javascript:display('player#{player_id}')" }
          script_array << "\"player#{player_id}\""

          td player[:total_units]
          td player[:next_units]
        end if player[:total_units] > 0
      end
    end

    text <<-SCRIPT
      <script>
        var players = new Array(#{script_array.join(',')});
        function display(player) {
          for (p in players) {
            document.getElementById(players[p]).style.display = 'none'
          }
          document.getElementById(player).style.display = 'block'
        }
      </script>
    SCRIPT

    @players.keys.each do |player_id|
      _player_detail(player_id)
    end
  end

  def _player_detail(player_id)
    board = @board.select {|_,c| c['playerid'] == player_id }
    board = board.sort_by {|_,c| c[:bonus_units] }.reverse

    return if board.empty?

    div(:id => "player#{player_id}", :style => 'display:none') do
      h3 @players[player_id][:name]

      table do
        tr do
          th 'Country'
          th 'Units'
        end

        board.each do |_,country|
          tr do
            td { _country(country) }
            td country[:bonus_units]
          end if country[:bonus_units] > 0
        end
      end
    end
  end

  def _country(country)
    a @country_names[country['id']], :href => "http://warfish.net/war/play/gamedetails?gid=#{@game_id}&t=m&cid=#{country['id']}"
  end
end
