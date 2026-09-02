# frozen_string_literal: true
#
# irb からるりま(Ruby リファレンスマニュアル)を引く refe コマンド。
# ~/.irbrc に `require "bitclust/irb"` と書くと irb に `refe` コマンドが
# 登録される。検索対象の DB は refe コマンドと同じ場所
# (bitclust setup が作る ~/.bitclust/config)から探し、DB が無ければ
# docs.ruby-lang.org の Markdown 配信から取得する(BitClust::Irb::Remote)。

require 'stringio'
require 'bitclust'
require 'bitclust/searcher'
require 'bitclust/irb/remote'

module BitClust
  module Irb
    USAGE = <<~USAGE
      Usage: refe <pattern>

      例:
        refe String#gsub     インスタンスメソッド
        refe Array.new       特異メソッド
        refe Comparable      クラス・モジュール
        refe printf          名前だけでの検索

      DB が無い場合は docs.ruby-lang.org から取得します(名前だけの検索は
      できません)。`bitclust setup` で DB を作ると手元で検索できます。
    USAGE

    NO_DATABASE_MESSAGE = <<~MSG
      DB が見つかりません。`bitclust setup` で作成してください。
      (docs.ruby-lang.org からの取得は BitClust::Irb.remote_base_url が nil のため無効です)
    MSG

    class << self
      # DB が無いときに取得する docs.ruby-lang.org の版の URL(末尾 / まで)。
      # nil にするとフォールバックしない。.md を配信しているのは latest だけ
      attr_accessor :remote_base_url
    end
    self.remote_base_url = Remote::DEFAULT_BASE_URL

    def self.default_remote
      url = remote_base_url
      url ? Remote.new(base_url: url) : nil
    end

    # pattern を検索して整形済みテキストを io へ書く。db が nil なら
    # 既定の場所から探し、そこにも無ければ remote(省略時は
    # default_remote。nil ならフォールバックしない)から取得する。
    # 検索の失敗は例外にせず io へメッセージを書く(irb セッションを
    # 止めないため)
    def self.lookup(pattern, io: $stdout, db: nil, remote: default_remote)
      words = pattern.to_s.split
      if words.empty?
        io.puts USAGE
        return
      end
      searcher = Searcher.new
      if db || searcher.local_database?
        view = TerminalView.new(Plain.new,
                                { describe_all: false, line: false, encoding: nil },
                                io: io)
        searcher.run_query(db, words, view)
      elsif remote
        remote.lookup(words, io)
      else
        io.puts NO_DATABASE_MESSAGE
      end
    rescue BitClust::UserError => err
      io.puts err.message
    end

    begin
      require 'irb/command'
    rescue LoadError
      # irb が無い(または irb < 1.13 で公開コマンド API が無い)環境では
      # コマンド登録だけを諦め、Irb.lookup は使えるままにする
    else
      class RefeCommand < ::IRB::Command::Base
        category 'Documentation'
        description 'るりま(Ruby リファレンスマニュアル)を検索して表示します'
        help_message USAGE

        def execute(arg)
          content = StringIO.new
          BitClust::Irb.lookup(arg, io: content)
          if ::IRB.const_defined?(:Pager)
            ::IRB::Pager.page_content(content.string)
          else
            $stdout.puts content.string
          end
        end
      end

      ::IRB::Command.register(:refe, RefeCommand)
    end
  end
end
