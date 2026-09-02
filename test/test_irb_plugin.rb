# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/searcher'
require 'bitclust/irb'

# bitclust-irb gem の irb コマンド(refe)。
#
# テストリスト:
# [x] TerminalView が io: に出力する(既定は従来どおり $stdout)
# [x] Irb.lookup がメソッドを検索して整形結果を io へ書く
# [x] Irb.lookup がクラスも引ける
# [x] 空のパターンは使い方を表示して例外にしない
# [x] 見つからないパターンはメッセージを io へ書いて例外にしない
# [x] require で IRB::Command::Base のサブクラスとして登録される
#
# HTTP フォールバック(ローカル DB が無いとき docs.ruby-lang.org の md 配信を引く):
# [x] Searcher#local_database? は既定の場所に DB が無ければ false・あれば true
# [x] Remote: メソッド指定を .md の URL に変換する(String#gsub → method/String/i/gsub.md)
# [x] Remote: 特異メソッド・module function(?. と .#)・定数・特殊変数・ネストしたクラス・演算子
# [x] Remote: 種別なしの 2 語は i → s → m → c の順に候補にする
# [x] Remote: 3 語の種別は typemark として検査する(不正なら InvalidKey)
# [x] Remote: 大文字始まりの 1 語はクラス → Kernel の module function の順
# [x] Remote: 小文字始まりの 1 語はライブラリ → Kernel の module function の順
# [x] Remote: Foo::Bar はクラス → 定数の順
# [x] Remote: 最初に 200 が返った候補の本文と出典 URL を io へ書く
# [x] Remote: 取得した本文は UTF-8 として扱う
# [x] Remote: 全候補が 404 なら検索ページの URL を案内し例外にしない
# [x] Remote: 接続エラーはメッセージ表示に留めて例外にしない
# [x] Remote: 非 ASCII の語は候補を作らず検索ページの URL を案内する
# [x] Irb.lookup: db が与えられていれば remote を使わない
# [x] Irb.lookup: ローカル DB が無ければ remote にフォールバックする
# [x] Irb.lookup: remote が nil なら bitclust setup を案内する
# [x] Irb.remote_base_url を nil にすると default_remote は nil
class TestBitClustIrbPlugin < Test::Unit::TestCase
  FOO_MD = <<~'MD'
    ---
    library: foo
    ---
    # class Foo < Object

    クラスの説明。

    ## Instance Methods

    ### def bar -> nil

    bar の説明。
  MD

  BASE_URL = 'https://docs.ruby-lang.org/ja/latest/'

  def build_markdown_db(dir)
    api = File.join(dir, 'manual', 'api')
    FileUtils.mkdir_p(File.join(api, 'foo'))
    File.write(File.join(api, 'foo.md'), "---\ntype: library\n---\nfoo ライブラリ。\n")
    File.write(File.join(api, 'foo', 'Foo.md'), FOO_MD)
    prefix = File.join(dir, 'db')
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_markdowntree(api)
    end
    BitClust::MethodDatabase.new(prefix)
  end

  def with_db(&block)
    Dir.mktmpdir do |dir|
      yield build_markdown_db(dir)
    end
  end

  # 既定の DB 探索(環境変数・~/.bitclust/config)がどれも当たらない状態
  DB_ENV_KEYS = %w[REFE2_SERVER BITCLUST_SERVER REFE2_DATADIR BITCLUST_DATADIR HOME].freeze

  def without_local_db
    saved = DB_ENV_KEYS.to_h {|k| [k, ENV[k]] }
    Dir.mktmpdir do |home|
      DB_ENV_KEYS.each {|k| ENV.delete(k) }
      ENV['HOME'] = home
      yield
    end
  ensure
    saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  # pages: base_url からの相対パス => 本文。無いパスは 404
  def fake_fetcher(pages, requested = [])
    lambda do |uri|
      requested << uri.to_s
      rel = uri.to_s.delete_prefix(BASE_URL)
      pages.key?(rel) ? [200, pages[rel]] : [404, '<Error><Code>AccessDenied</Code></Error>']
    end
  end

  def remote(pages, requested = [])
    BitClust::Irb::Remote.new(base_url: BASE_URL, fetcher: fake_fetcher(pages, requested))
  end

  def test_terminal_view_writes_to_given_io
    out = StringIO.new
    view = BitClust::TerminalView.new(BitClust::Plain.new, {}, io: out)
    view.send(:puts, 'hello')
    assert_equal("hello\n", out.string)
  end

  def test_lookup_method
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo#bar', db: db, io: out)
      assert_match(/Foo#bar/, out.string)
      assert_match(/bar の説明。/, out.string)
    end
  end

  def test_lookup_class
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo', db: db, io: out)
      assert_match(/class Foo < Object/, out.string)
      assert_match(/クラスの説明。/, out.string)
    end
  end

  def test_lookup_empty_pattern_shows_usage
    with_db do |db|
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('', db: db, io: out)
      end
      assert_match(/refe/, out.string)
    end
  end

  def test_lookup_not_found_reports_instead_of_raising
    with_db do |db|
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('NoSuchClass#no_such_method', db: db, io: out)
      end
      assert_match(/no such method/, out.string)
    end
  end

  def test_command_is_registered_for_irb
    begin
      require 'irb/command'
    rescue LoadError
      omit 'irb >= 1.13 is not available'
    end
    assert(BitClust::Irb::RefeCommand < ::IRB::Command::Base)
    assert_match(/るりま|リファレンス/, BitClust::Irb::RefeCommand.description)
  end

  def test_searcher_local_database_p
    without_local_db do
      assert_false(BitClust::Searcher.new.local_database?)
      with_db do |db|
        ENV['BITCLUST_DATADIR'] = db.instance_variable_get(:@prefix)
        assert_true(BitClust::Searcher.new.local_database?)
      end
    end
  end

  def test_remote_candidate_paths_for_method_specs
    r = remote({})
    assert_equal(['method/String/i/gsub.md'], r.candidate_paths(%w[String#gsub]))
    assert_equal(['method/Array/s/new.md'], r.candidate_paths(%w[Array.new]))
    assert_equal(['method/Kernel/m/printf.md'], r.candidate_paths(%w[Kernel.#printf]))
    assert_equal(['method/Kernel/m/printf.md'], r.candidate_paths(%w[Kernel?.printf]))
    assert_equal(['method/Kernel/v/stdout.md'], r.candidate_paths(%w[$stdout]))
    assert_equal(['method/Net=3a=3aHTTP/i/get.md'], r.candidate_paths(%w[Net::HTTP#get]))
    assert_equal(['method/Array/i/=3d=3d.md'], r.candidate_paths(%w[Array#==]))
    assert_equal(['method/String/i/=5b=5d.md'], r.candidate_paths(%w[String#[]]))
  end

  def test_remote_candidate_paths_without_type
    r = remote({})
    assert_equal(%w[method/String/i/gsub.md method/String/s/gsub.md
                    method/String/m/gsub.md method/String/c/gsub.md],
                 r.candidate_paths(%w[String gsub]))
    assert_equal(['method/String/s/new.md'], r.candidate_paths(%w[String . new]))
    assert_raise(BitClust::InvalidKey) { r.candidate_paths(%w[String $ new]) }
    assert_raise(BitClust::InvalidKey) { r.candidate_paths(%w[String x new]) }
  end

  def test_remote_candidate_paths_for_single_word
    r = remote({})
    assert_equal(%w[class/String.md method/Kernel/m/String.md], r.candidate_paths(%w[String]))
    assert_equal(%w[library/json.md method/Kernel/m/json.md], r.candidate_paths(%w[json]))
    assert_equal(%w[library/net=2fhttp.md method/Kernel/m/net=2fhttp.md], r.candidate_paths(%w[net/http]))
    assert_equal(%w[class/File=3a=3aStat.md method/File/c/Stat.md], r.candidate_paths(%w[File::Stat]))
  end

  def test_remote_lookup_writes_first_hit_with_source_url
    requested = []
    pages = {
      'method/String/s/gsub.md' => "# String.gsub\n\nダミー\n",
      'method/String/i/gsub.md' => "# String#gsub\n\n### def gsub(pattern, replace) -> String\n\n置き換えます。\n",
    }
    out = StringIO.new
    assert_true(remote(pages, requested).lookup(%w[String gsub], out))
    assert_equal(["#{BASE_URL}method/String/i/gsub.md"], requested)
    assert_match(/\A# String#gsub$/, out.string)
    assert_match(/置き換えます。/, out.string)
    assert_match(%r{^https://docs.ruby-lang.org/ja/latest/method/String/i/gsub.html$}, out.string)
    assert_not_match(/ダミー/, out.string)
  end

  def test_remote_lookup_tries_candidates_in_order
    requested = []
    pages = { 'method/Kernel/m/printf.md' => "# Kernel?.printf\n\n出力します。\n" }
    out = StringIO.new
    assert_true(remote(pages, requested).lookup(%w[printf], out))
    assert_equal(["#{BASE_URL}library/printf.md", "#{BASE_URL}method/Kernel/m/printf.md"], requested)
    assert_match(/出力します。/, out.string)
  end

  def test_remote_find_returns_utf8_body
    pages = { 'class/String.md' => "# class String < Object\n\n文字列のクラスです。\n".b }
    url, body = remote(pages).find(%w[String])
    assert_equal("#{BASE_URL}class/String.html", url)
    assert_equal(Encoding::UTF_8, body.encoding)
    assert_true(body.valid_encoding?)
    assert_match(/文字列のクラスです。/, body)
  end

  def test_remote_lookup_not_found_shows_search_url
    out = StringIO.new
    assert_nothing_raised do
      assert_false(remote({}).lookup(%w[NoSuchClass#nope], out))
    end
    assert_match(/NoSuchClass#nope/, out.string)
    assert_match(%r{https://docs.ruby-lang.org/ja/search/\?q=NoSuchClass%23nope}, out.string)
  end

  def test_remote_lookup_non_ascii_word_shows_search_url
    out = StringIO.new
    r = BitClust::Irb::Remote.new(base_url: BASE_URL, fetcher: ->(_uri) { flunk "must not fetch" })
    assert_equal([], r.candidate_paths(%w[文字列]))
    assert_false(r.lookup(%w[文字列], out))
    assert_match(%r{https://docs.ruby-lang.org/ja/search/\?q=%E6%96%87%E5%AD%97%E5%88%97}, out.string)
  end

  def test_remote_lookup_reports_network_errors
    failing = BitClust::Irb::Remote.new(base_url: BASE_URL,
                                        fetcher: ->(_uri) { raise SocketError, 'getaddrinfo: Name or service not known' })
    out = StringIO.new
    assert_nothing_raised do
      assert_false(failing.lookup(%w[String#gsub], out))
    end
    assert_match(/docs\.ruby-lang\.org/, out.string)
    assert_match(/getaddrinfo/, out.string)
    assert_match(/bitclust setup/, out.string)
  end

  def test_lookup_uses_local_db_when_given
    never = BitClust::Irb::Remote.new(base_url: BASE_URL,
                                      fetcher: ->(_uri) { flunk 'remote must not be used' })
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo#bar', db: db, io: out, remote: never)
      assert_match(/bar の説明。/, out.string)
    end
  end

  def test_lookup_falls_back_to_remote_without_local_db
    pages = { 'method/String/i/gsub.md' => "# String#gsub\n\n置き換えます。\n" }
    without_local_db do
      out = StringIO.new
      BitClust::Irb.lookup('String#gsub', io: out, remote: remote(pages))
      assert_match(/置き換えます。/, out.string)
    end
  end

  def test_lookup_without_remote_and_local_db_shows_setup_hint
    without_local_db do
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('String#gsub', io: out, remote: nil)
      end
      assert_match(/bitclust setup/, out.string)
    end
  end

  def test_default_remote_follows_remote_base_url
    saved = BitClust::Irb.remote_base_url
    assert_equal(BASE_URL, saved)
    assert_kind_of(BitClust::Irb::Remote, BitClust::Irb.default_remote)
    BitClust::Irb.remote_base_url = nil
    assert_nil(BitClust::Irb.default_remote)
  ensure
    BitClust::Irb.remote_base_url = saved
  end
end
