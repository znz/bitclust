# るりま Markdown 記法仕様（案）

本文書は、Ruby リファレンスマニュアル（るりま）のドキュメント形式を
RD ベースの独自記法（RRD）から Markdown ベースの記法へ移行するための仕様を定める。

## 背景と方針

- **ベース仕様**: GitHub Flavored Markdown (GFM)
- **プリプロセッサ**: 既存の `#@` 指令を維持（Liquid には依存しない）
- **移行戦略**: まず Markdown → RD 変換レイヤーを構築して既存 bitclust 上で記法を検証し、
  段階的に Markdown 記法への移行を進め、最終的に bitclust に依存しない新システムへ移行する
- **設計原則**:
  - 処理系に依存しない記法を選択する
  - 構造データは YAML front matter に集約する
  - 本文は極力標準 GFM に従い、独自拡張を最小限にする
  - 既存の Markdown エコシステム（エディタ、プレビュー）との互換性を重視する

## 前回調査（2022-2023）からの変更点

| 項目 | 前回（bitclust markdown 記法） | 本仕様 |
|------|-------------------------------|--------|
| プリプロセッサ | Liquid (`{% if %}`) | `#@since`/`#@until`/`#@if` を維持 |
| コメント | `{% comment %}` | `#@#` を維持 |
| include | Liquid `{% include %}` 予定 | `#@include` を維持 |
| `include`/`extend`/`alias` | 未定 | H1 直後にそのまま維持（将来 front matter へ） |
| メソッドシグネチャ | `def` のみ | `def`/`const`/`gvar`/`module_function def` |
| モジュール関数参照 | 未定 | `[m:Kernel?.open]`（RBS `self?` 由来） |
| `@param` 記法 | `* *param* name -- 説明` | `` - **param** `name` -- 説明 `` |
| `@see` 記法 | 未定 | `- **SEE** [リンク]`（リスト形式） |
| アンカー | 未定 | `{#id}`（kramdown/Pandoc 互換） |
| コードブロックラベル | 未対応 | `title="ラベル"` |

---

## 1. YAML Front Matter

ファイル冒頭に `---` で囲まれた YAML ブロックを置き、メタデータを記述する。
front matter は任意であり、メタデータがない場合は省略できる。

### 1.1 ライブラリメタデータ

ライブラリファイル（`refm/api/src/` 直下）で使用する。

```yaml
---
category: Network
require:
  - cgi/core
  - cgi/cookie
sublibrary:
  - rubygems/gem_runner
---
```

| キー | 型 | 説明 |
|------|-----|------|
| `category` | String | ライブラリのカテゴリ |
| `require` | String[] | 依存ライブラリのリスト |
| `sublibrary` | String[] | サブライブラリのリスト |

`require`/`sublibrary` は常に配列形式で記述する（単一でも配列）。

### 1.2 クラス/モジュールメタデータ

`include`/`extend`/`alias` は RRD と同じく H1 直後に記述する（front matter には含めない）。
1ファイルに複数のクラス定義がある場合でも正しく対応できる。

```markdown
# class Array < Object
include Enumerable

配列クラスです。
```

将来、1ファイル1クラスへの分割後に front matter への移行を検討する。

### 1.3 front matter 内のバージョン分岐

`#@since`/`#@until`/`#@end` は YAML のコメント（`#` 始まり）として
有効であるため、front matter 内でも使用できる。

**処理順序**: 前処理（`#@` 指令の解決）→ YAML パース → Markdown パース

---

## 2. 見出し構造

ATX 形式（`# heading`）のみを使用する。Setext 形式は使用しない。

### 2.1 見出しレベルの対応

| レベル | 用途 | 例 |
|--------|------|-----|
| `#` (h1) | クラス/モジュール/オブジェクト定義 | `# class Array < Object` |
| `##` (h2) | メソッドカテゴリ | `## Instance Methods` |
| `###` (h3) | メソッドシグネチャ / 本文小見出し | `### def each` / `### 破壊的な変更 {#mutable}` |
| `####` (h4) | 本文のさらに深い小見出し | `#### 文字列同士の比較・結合` |
| `#####` (h5) | 本文の最深小見出し（稀） | `##### まとめ` |

### 2.2 クラス/モジュール定義（h1）

```markdown
# class Array < Object
# module Comparable
# module Kernel
# object ENV
# reopen Kernel
```

`class`、`module`、`object`、`reopen` のキーワードで種別を示す。
継承関係は `< SuperClass` で記述する。

### 2.3 メソッドカテゴリ（h2）

```markdown
## Class Methods
## Instance Methods
## Module Functions
## Constants
## Special Variables
## Private Instance Methods
## Protected Instance Methods
```

### 2.4 本文小見出しとアンカー

本文中の小見出しには kramdown/Pandoc 互換の `{#id}` でアンカーを付与できる。

```markdown
### 多言語化と文字列のエンコーディング {#m17n}
#### 文字列同士の比較・結合
```

アンカーへの参照は標準 Markdown リンクで行う: `[テキスト](#m17n)`

---

## 3. メソッドシグネチャ

h3 レベル（`###`）で記述する。キーワード（`def`/`const`/`gvar`/`module_function def`）の
有無と種類で本文小見出しおよびエントリの種別を区別する。

### 3.1 Ruby 構文形式

```markdown
### def each {|item| ... } -> self
### def Array.try_convert(obj) -> Array | nil
### def self.new(size = 0, val = nil) -> Array
### module_function def measure(label) -> Benchmark::Tms
### const CR -> String
### gvar $DEBUG -> bool
```

| メソッド種別 | 記法 | 区別方法 |
|-------------|------|---------|
| インスタンスメソッド | `### def method(args)` | `def` キーワード |
| クラスメソッド / 特異メソッド | `### def ClassName.method(args)` | `def` + `ClassName.` |
| クラスメソッド（RBS 互換） | `### def self.method(args)` | `def` + `self.` |
| モジュール関数 | `### module_function def method(args)` | `module_function def` |
| 定数 | `### const CONST -> Type` | `const` キーワード |
| グローバル変数 | `### gvar $VAR -> Type` | `gvar` キーワード |
| 本文小見出し | `### 見出しテキスト` | キーワードなし |

RRD との相互変換では `ClassName.method` をそのまま保持する（`self.` への変換はしない）。

### 3.2 RBS 形式

`:` の位置で Ruby 構文形式と区別する。

```markdown
### def self.try_convert: (untyped obj) -> Array[untyped]?
### def each: () { (untyped) -> void } -> self
```

| 判定基準 | 形式 |
|---------|------|
| `def name(` または `def name ->` | Ruby 構文 |
| `def name:` | RBS |

### 3.3 定数

`const` キーワードを付ける。

```markdown
### const CR -> String
### const NEEDS_BINMODE -> bool
```

### 3.4 グローバル変数

`gvar` キーワードを付ける。

```markdown
### gvar $DEBUG -> bool
### gvar $ERROR_INFO -> Exception | nil
```

### 3.5 モジュール関数

`module_function def` キーワードを付ける。

```markdown
### module_function def measure(label) -> Benchmark::Tms
### module_function def realtime { ... } -> Float
```

### 3.6 エイリアスメソッド

同一メソッドの別名は `###` 行を連続して記述する。

```markdown
### def [](nth) -> object | nil
### def at(nth) -> object | nil

nth 番目の要素を返します。
```

### 3.7 バージョン分岐を含むシグネチャ

```markdown
### def self.new(string = "") -> String
#@since 2.4.0
### def self.new(string = "", encoding: string.encoding, capacity: 127) -> String
#@end
```

---

## 4. メソッドエントリの構造

各メソッドエントリは以下の順序で構成する。
（[ReferenceManualFormatDigest](https://github.com/rurema/doctree/wiki/ReferenceManualFormatDigest) に準拠）

1. **シグネチャ**（必須）: `### def method(args) -> Type`
2. **要約**（必須）: 1段落での概要説明
3. **詳細説明**: 追加の説明文（任意）
4. **param/return/raise**: パラメータ・返り値・例外の説明
5. **注意事項**: 追加の警告など（任意）
6. **使用例**: サンプルコード
7. **SEE**: 関連メソッド参照（リスト形式）

---

## 5. パラメータ・返り値・例外

`@param`/`@return`/`@raise` に代わるリスト形式で記述する。
`@` プレフィクスは使用しない（GitHub issue/PR でのメンション誤爆を回避）。

### 5.1 基本形式

```markdown
- **param** `name` -- 説明文
- **return** -- 説明文
- **return** `Type` -- 説明文
- **raise** `ExceptionClass` -- 説明文
```

- 種別ラベルはボールド体: `**param**`, `**return**`, `**raise**`
- パラメータ名・例外クラス名はコードスパン: `` `name` ``, `` `TypeError` ``
- 区切りは `--`（ASCII ハイフン2つ）
- 複数行の説明はインデントで継続

### 5.2 例

```markdown
- **param** `nth` -- インデックスを整数で指定します。
           先頭の要素が 0 番目になります。nth の値が負の時には末尾から
           のインデックスと見倣します。
- **param** `val` -- 設定したい要素の値を指定します。
- **return** `String` -- 変換後の文字列
- **return** `nil` -- 変換できなかった場合
- **raise** `TypeError` -- 引数に整数以外のオブジェクトを指定した場合に発生します。
- **raise** `IndexError` -- 指定された nth が自身の始点よりも前を指している場合に発生します。
```

---

## 6. SEE（関連メソッド参照）

param/raise と同様にリスト形式で記述する。
HTMLでの `[SEE_ALSO]` 表示に対応し、大文字のボールド体とする。

```markdown
- **SEE** [m:String#-@]
```

カンマ区切りの複数参照は1つの SEE 項目内にそのまま保持する:

```markdown
- **SEE** [m:String#encode], [m:String#encode!]
```

RRDの `@see` が複数行に分かれている場合は個別の項目になる:

```markdown
- **SEE** [m:CGI.accept_charset]
- **SEE** [m:CGI.accept_charset=]
```

---

## 7. クロスリファレンス（ハイパーリンク）

RRD の `[[type:target]]` から角括弧を1段減らし `[type:target]` とする。
前回調査（2022-2023）の設計を踏襲。

### 7.1 記法一覧

| 種別 | 記法 | 例 |
|------|------|-----|
| クラス | `[c:ClassName]` | `[c:String]` |
| メソッド | `[m:Class#method]` | `[m:Array#each]` |
| クラスメソッド | `[m:Class.method]` | `[m:CGI.accept_charset]` |
| モジュール関数 | `[m:Class?.method]` | `[m:Kernel?.open]` |
| ライブラリ | `[lib:name]` | `[lib:json]` |
| C 関数 | `[f:name]` | `[f:rb_str_new]` |
| ドキュメント | `[d:path]` | `[d:spec/m17n]` |
| ドキュメント+アンカー | `[d:path#anchor]` | `[d:spec/m17n#m17n]` |
| RFC | `[RFC:number]` | `[RFC:822]` |
| man ページ | `[man:command(section)]` | `[man:grep(1)]` |
| ML | `[ruby-list:number]` | `[ruby-list:35911]` |
| bugs.ruby-lang.org | `[feature:number]` | `[feature:12345]` |

モジュール関数の `?` は RBS の `self?` に由来し、RRD の `.#` typemark に対応する。

### 7.2 メソッド名のエスケープ

メソッド名に `[` `]` `\` を含む場合はバックスラッシュでエスケープする。

```markdown
[m:Hash#\[\]]          ← Hash#[]
[m:String#\[\]=]       ← String#[]=
[m:$\\]                ← $\
```

### 7.3 表示テキスト付きリンク（将来対応予定）

Markdown のリンク記法を活用して表示テキストを指定できる:

```markdown
[Array#dup][m:Array#dup]
[spec/m17n][d:spec/m17n]
```

現在の変換器は bare ref (`[type:target]`) のみ生成・変換する。
表示テキスト付きリンクの対応は Markdown 移行後に行う。

### 7.4 外部 URL

通常の Markdown リンク記法を使用する:

```markdown
<https://example.com>
[例示ドメイン](https://example.com)
```

### 7.5 ファイル内アンカー参照

標準 Markdown のフラグメントリンクを使用する:

```markdown
[破壊的な変更](#mutable)
```

---

## 8. プリプロセッサ指令

既存の `#@` 指令をそのまま維持する。
`#@` は CommonMark で見出し（ATX heading）として解釈されないため安全である
（ATX heading は `#` の後にスペースが必要）。

### 8.1 バージョン条件

```markdown
#@since 3.0
（Ruby 3.0 以降の内容）
#@end

#@until 3.2
（Ruby 3.2 より前の内容）
#@end

#@if (version >= "3.1")
（条件を満たす場合の内容）
#@else
（条件を満たさない場合の内容）
#@end
```

### 8.2 ファイルインクルード

```markdown
#@include(io/buffer.md)
```

### 8.3 コメント

```markdown
#@# これはコメント（出力されない）
```

### 8.4 処理順序

**前処理 → YAML front matter パース → Markdown パース → HTML 生成**

前処理はテキストレベルで行われるため、Markdown の構文要素（コードブロック等）の
中にある `#@` 指令も処理される。これは RRD と同じ挙動である。

---

## 9. コードブロック

GFM 標準のフェンスドコードブロックを使用する。

### 9.1 基本形式

````markdown
```ruby
puts "hello"
```
````

### 9.2 ラベル（タイトル）

info string の `title=` 属性でラベルを付与する。
これは Docusaurus、MkDocs Material、Hugo、Expressive Code 等で
採用されているデファクトスタンダードである。

````markdown
```ruby title="nil を渡す例"
5.clamp(0, nil)          #=> 5
5.clamp(nil, 0)          #=> 0
```
````

`title=` 非対応の処理系では無視される（表示上の劣化のみで情報は失われない）。

### 9.3 RRD インデントコードブロック

RRD ではインデントされたテキストが整形済みテキスト（`<pre>`）になる。
Markdown ではバッククォートの個数で元のインデント幅をエンコードする。

````
N個のバッククォート = 3 + 元のインデント幅

例: 2スペースインデント → 5個のバッククォート
`````
code line 1
code line 2
`````
````

コードブロック内のベースインデントは除去される。
逆変換時はバッククォートの個数からインデント幅を復元する。

### 9.4 RRD からの変換一覧

| RRD | Markdown |
|-----|----------|
| `#@samplecode ラベル` ... `#@end` | ```` ```ruby title="ラベル" ```` ... ```` ``` ```` |
| `#@samplecode` ... `#@end` | ```` ```ruby ```` ... ```` ``` ```` |
| `//emlist[ラベル][lang]{` ... `//}` | ```` ```lang title="ラベル" ```` ... ```` ``` ```` |
| インデントテキスト（Nスペース） | `(3+N)` 個のバッククォートで囲む |

### 9.5 インラインコード

テキスト行中の `__WORD__` パターン（`__END__`, `__FILE__` 等）は
自動的にコードスパンに変換される。ブラケットリンク内の `__WORD__` は変換しない。

---

## 10. 通常のテキスト

GFM の記法に従う。

### 10.1 リスト

```markdown
- 項目1
- 項目2
  - ネストした項目
```

番号付きリストは GFM 標準の形式を使用する。
RRD の ` (1)` 形式に対応する。

```markdown
1. 最初の項目
2. 次の項目
3. 最後の項目
```

段落で分断された番号付きテキスト（RRD で `N.` 形式）は、
Markdown で番号付きリストに誤解釈されないよう太字番号で記述する。

```markdown
**1.** クラス定義の中で、Exception2MessageMapper を extend すれば、
def_e2message メソッドや def_exception メソッドが使えます。

例:
...

**2.** 何度も使いたい例外クラスは、クラスの代わりにモジュールで定義して、
それを include して使います。
```

### 10.2 定義リスト的な記述

RRD の定義リスト（`: term` / `  definition`）に相当する記法として、
ボールドリストを使用する。GFM は定義リストに未対応のため、
GFM 互換のリスト形式で記述する。

```markdown
- **`type`**: Content-Type ヘッダです。デフォルトは "text/html" です。
- **`charset`**: ボディのキャラクタセットを Content-Type ヘッダに追加します。
```

短い英数字/記号の term（40文字未満、日本語を含まない）は自動的にコードスパン化される: `` **`term`** ``。
日本語を含む term や長い term はプレーンテキスト: `**term**`。

`` - **param** `name` -- 説明 `` との区別:
- 定義リスト: `` - **`term`**: description ``（コロン区切り）
- メタデータ: `` - **param** `name` -- description ``（ダブルハイフン区切り）

### 10.3 テーブル

GFM テーブルを使用できる。

```markdown
| 文字列 | ステータス |
|--------|-----------|
| `"OK"` | `"200 OK"` |
```

---

## 11. パーサーの見出し判定ロジック

h3 行の種別判定（キーワードベース）:

```
1. `### module_function def ` → モジュール関数
2. `### def ` → メソッドシグネチャ
   - `def name:` → RBS 形式
   - `def ClassName.name` or `def self.name` → クラスメソッド / 特異メソッド
   - `def name` → インスタンスメソッド
3. `### const ` → 定数
4. `### gvar ` → グローバル変数
5. それ以外の `### ` → 本文小見出し
```

キーワードの有無で明確に区別できるため、セクションコンテキスト（`## Constants` 等）
による文脈依存の判定は不要。

---

## 12. RRD との記法対応表

| RRD | Markdown | 備考 |
|-----|----------|------|
| `= class Foo < Bar` | `# class Foo < Bar` | h1 |
| `== Instance Methods` | `## Instance Methods` | h2 |
| `--- method(args) -> Type` | `### def method(args) -> Type` | `def` キーワード |
| `--- ClassName.method(args)` | `### def ClassName.method(args)` | クラスメソッド |
| Module Functions 内 `--- method` | `### module_function def method` | モジュール関数 |
| `--- CONST -> Type` | `### const CONST -> Type` | `const` キーワード |
| `--- $VAR -> Type` | `### gvar $VAR -> Type` | `gvar` キーワード |
| `===[a:name] 見出し` | `### 見出し {#name}` | kramdown/Pandoc 互換 |
| `==== 小見出し` | `#### 小見出し` | h4 |
| `include Mod` | `include Mod` | **そのまま維持** |
| `extend Mod` | `extend Mod` | **そのまま維持** |
| `alias Name` | `alias Name` | **そのまま維持** |
| `category Cat` | front matter `category: Cat` | YAML |
| `require lib` | front matter `require: [lib]` | YAML |
| `sublibrary lib` | front matter `sublibrary: [lib]` | YAML |
| `[[c:String]]` | `[c:String]` | 角括弧1段減 |
| `[[m:Array#each]]` | `[m:Array#each]` | 角括弧1段減 |
| `[[m:Kernel.#open]]` | `[m:Kernel?.open]` | `.#` → `?` |
| `[[m:Hash#[] ]]` | `[m:Hash#\[\]]` | `\` エスケープ |
| `[[ref:name]]` | `[テキスト](#name)` | 標準 Markdown リンク |
| `@param name 説明` | `` - **param** `name` -- 説明 `` | リスト形式 |
| `@return 説明` | `- **return** -- 説明` | リスト形式 |
| `@raise Ex 説明` | `` - **raise** `Ex` -- 説明 `` | リスト形式 |
| `@see [[m:...]]` | `- **SEE** [m:...]` | リスト形式 |
| `#@since VER` | `#@since VER` | **そのまま維持** |
| `#@until VER` | `#@until VER` | **そのまま維持** |
| `#@if (cond)` | `#@if (cond)` | **そのまま維持** |
| `#@else` | `#@else` | **そのまま維持** |
| `#@end` | `#@end` | **そのまま維持** |
| `#@include(file)` | `#@include(file)` | **そのまま維持** |
| `#@#` | `#@#` | **そのまま維持** |
| `#@samplecode ラベル` | ```` ```ruby title="ラベル" ```` | Ruby コード |
| `//emlist[cap][lang]{` | ```` ```lang title="cap" ```` | 非 Ruby コード |
| `* item` | `- item` | GFM リスト |
| `(1) item` | `1. item` | GFM 番号付きリスト |
| `N. text`（離散） | `**N.** text` | 太字番号テキスト |
| `: term` / `  def` | `` - **`term`**: def `` | ボールドリスト |

---

## 13. サンプルファイル

本仕様に基づくサンプルファイルは `doc/markdown-samples/` ディレクトリに格納されている。
各ファイルは `bin/rrd2md` による実際の RRD→MD 変換出力から生成されたものである。

| ファイル | 元ファイル | 検証内容 |
|---------|-----------|---------|
| `Comparable.md` | `_builtin/Comparable` | module、since/until、param/raise、title=、module_function |
| `Array.md` | `_builtin/Array` | class、include、class/instance methods、複数シグネチャ、const |
| `String.md` | `_builtin/String` | 本文小見出し(`###`/`####`)、アンカー `{#id}`、複雑なバージョン分岐、**SEE** |
| `cgi_core.md` | `cgi/core.rd` | ライブラリサブファイル、定義リスト、定数、GFM テーブル、**SEE** |

---

## 14. 未決事項・今後の検討

### 解決済み

- [x] RD ↔ MD 双方向変換器の実装（826/826 ファイルでロスレスラウンドトリップ達成）
- [x] 定義リストの Markdown 記法（GFM 互換の `` - **`term`**: description `` 形式を採用）
- [x] 複数行にまたがるリスト項目の Markdown 表示品質改善（継続行対応済み）
- [x] `@param`/`@see` 等の継続行が `#@` ディレクティブを挟む場合の対応（ネスト追跡で解決）
- [x] `[c:String]` 等のリンク記法（RRD `[[...]]` ↔ MD `[...]` の双方向変換で解決）
- [x] `include`/`extend`/`alias` の扱い（現時点ではパススルー、将来 front matter 移行）

### 未解決

- [ ] `#@include` での RD/MD 混在対応（段階的移行期の課題）
- [ ] エディタ支援: `#@` 指令用の VS Code TextMate grammar 作成
- [ ] プリプロセッサがコードブロック内の `#@` を処理する挙動の是非
  - 現行 RRD と同じ挙動だが、Markdown パーサーの結果を利用して
    コードブロック内の指令を区別すべきか要検討
- [ ] kramdown での `{#id}` 対応状況の詳細検証
- [ ] `refe` コマンド等でのプレーンテキスト表示時の可読性確認
- [ ] RBS 形式シグネチャの実運用テスト
- [ ] 新システム（bitclust 脱却後）のパーサー実装方針
- [ ] `include`/`extend`/`alias` の front matter 移行（1ファイル1クラス分割後）
