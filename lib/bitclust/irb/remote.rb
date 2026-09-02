# frozen_string_literal: true
#
# ローカル DB が無い環境向けの HTTP フォールバック。docs.ruby-lang.org の
# Markdown 配信(/ja/latest/ 配下の .md = statichtml --markdown-output の
# 生成物)から該当ページを 1 つ取得して表示する。refe の検索パターンを URL に
# 変換して順に試すだけなので、名前だけからクラスをまたいで探す検索
# (`refe each` でメソッド名の一覧を出す等)はできない。

require 'net/http'
require 'openssl'
require 'uri'
require 'bitclust/version'
require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust
  module Irb
    class Remote
      include NameUtils

      DEFAULT_BASE_URL = 'https://docs.ruby-lang.org/ja/latest/'
      SEARCH_URL = 'https://docs.ruby-lang.org/ja/search/'
      # 種別の指定が無いときに試す順(インスタンス・特異・module function・定数)
      TYPECHARS_WITHOUT_TYPE = %w[i s m c].freeze
      NETWORK_ERRORS = [SocketError, IOError, SystemCallError, Timeout::Error,
                        OpenSSL::SSL::SSLError, Net::ProtocolError].freeze

      attr_reader :base_url

      # fetcher は URI を受け取って [ステータス(Integer), 本文(String)] を返す
      # 呼び出し可能オブジェクト。省略時は Net::HTTP で取得する
      def initialize(base_url: DEFAULT_BASE_URL, fetcher: nil)
        @base_url = base_url.end_with?('/') ? base_url : "#{base_url}/"
        @fetcher = fetcher
      end

      # words のページを探して本文と出典 URL を io へ書く。見つかれば true。
      # 見つからない・接続できない場合はメッセージを書いて false(例外にしない)
      def lookup(words, io)
        found = find(words)
        if found
          url, body = found
          io.puts body
          io.puts
          io.puts '---'
          io.puts url
          io.puts '(ローカル DB が無いため docs.ruby-lang.org から取得しました。手元で検索するには bitclust setup で DB を作成してください)'
          true
        else
          io.puts "docs.ruby-lang.org に #{words.join(' ')} のページが見つかりませんでした。"
          io.puts '名前だけからクラスをまたいで探す検索にはローカル DB(bitclust setup)が必要です。'
          io.puts "検索ページ: #{search_url(words)}"
          false
        end
      rescue *NETWORK_ERRORS => err
        io.puts "docs.ruby-lang.org に接続できませんでした (#{err.class}: #{err.message})"
        io.puts 'オフラインで使うには bitclust setup で DB を作成してください。'
        false
      end

      # 候補 URL を順に取得し、最初に 200 が返ったページの
      # [HTML の URL, UTF-8 の本文] を返す。無ければ nil
      def find(words)
        fetcher = @fetcher
        return find_with(fetcher, words) if fetcher
        http = HttpFetcher.new
        begin
          find_with(http, words)
        ensure
          http.close
        end
      end

      # refe の検索パターン(1〜3 語)を base_url からの相対パスの候補に変換する。
      # ページ名に使えない非 ASCII の語は候補なし
      def candidate_paths(words)
        return [] unless words.all?(&:ascii_only?)
        case words.size
        when 1
          single_word_paths(words[0] || raise)
        when 2
          method_paths(words[0] || raise, nil, words[1] || raise)
        when 3
          c, t, m = words[0] || raise, words[1] || raise, words[2] || raise
          raise InvalidKey, "'$' cannot be used as method type" if t == '$'
          raise InvalidKey, "unknown method type: #{t.inspect}" unless typemark?(t)
          method_paths(c, t, m)
        else
          raise InvalidKey, "too many arguments (#{words.size} for 3)"
        end
      end

      def search_url(words)
        "#{SEARCH_URL}?q=#{URI.encode_www_form_component(words.join(' '))}"
      end

      private

      def find_with(fetcher, words)
        candidate_paths(words).each do |path|
          uri = URI("#{@base_url}#{path}")
          status, body = fetcher.call(uri)
          next unless status == 200
          return [uri.to_s.sub(/\.md\z/, '.html'), to_utf8(body)]
        end
        nil
      end

      # Searcher#find_class_or_method と同じ優先順位で候補を並べる
      def single_word_paths(pat)
        case pat
        when /\A\$/   # 特殊変数
          [method_path('Kernel', 'v', pat.sub(/\A\$/, ''))]
        when /[\#,]\.|\.[\#,]|[\#\.\,]/   # メソッド指定
          c, t, m = parse_method_spec_pattern(pat)
          method_paths(c, t, m)
        when /::/   # クラス名か定数名
          names = pat.split('::')
          name = names.pop || raise
          [class_path(pat), method_path(names.join('::'), 'c', name)]
        when /\A[A-Z]/   # クラス名が優先。Integer() のような Kernel の関数も
          [class_path(pat), method_path('Kernel', 'm', pat)]
        else   # ライブラリ名か Kernel の関数(printf 等)
          [library_path(pat), method_path('Kernel', 'm', pat)]
        end
      end

      def method_paths(c, t, m)
        chars = t ? [typemark2char(_ = t)] : TYPECHARS_WITHOUT_TYPE
        chars.map {|ch| method_path(c, ch, m) }
      end

      def method_path(c, typechar, m)
        "method/#{encodename_url(c)}/#{typechar}/#{encodename_url(m)}.md"
      end

      def class_path(c)
        "class/#{encodename_url(c)}.md"
      end

      def library_path(lib)
        "library/#{encodename_url(lib)}.md"
      end

      # 配信は text/markdown; charset=utf-8。Net::HTTP の本文は BINARY で返る
      def to_utf8(body)
        str = body.dup.force_encoding(Encoding::UTF_8)
        str.valid_encoding? ? str : str.scrub
      end

      # Net::HTTP による既定の取得。同じホストへの接続は使い回し、close で閉じる
      class HttpFetcher
        HEADERS = {
          'User-Agent' => "bitclust-irb/#{BitClust::VERSION}",
          'Accept' => 'text/markdown',
        }.freeze
        MAX_REDIRECTS = 2

        def initialize(open_timeout: 5, read_timeout: 15)
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @sessions = {}
        end

        def call(uri)
          redirects = 0
          loop do
            res = session(uri).get(uri.path || raise, HEADERS)
            location = res['location']
            if res.is_a?(Net::HTTPRedirection) && location && redirects < MAX_REDIRECTS
              redirects += 1
              uri = URI.join(uri, location)
            else
              return [res.code.to_i, res.body.to_s]
            end
          end
        end

        def close
          @sessions.each_value {|http| http.finish if http.started? }
          @sessions.clear
        end

        private

        def session(uri)
          @sessions[[uri.host, uri.port]] ||=
            Net::HTTP.start(uri.host || raise, uri.port,
                            use_ssl: uri.scheme == 'https',
                            open_timeout: @open_timeout,
                            read_timeout: @read_timeout)
        end
      end
    end
  end
end
