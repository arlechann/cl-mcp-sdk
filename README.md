# Mcp-Sdk

## 概要

このプロジェクトは、`stdio` 経由で動作する MCP サーバを実装するための
Common Lisp SDK です。

現在の対応範囲:

- `initialize` / `notifications/initialized` / `ping`
- `tools/list` / `tools/call`
- `resources/list` / `resources/read`
- `resources/templates/list`
- `prompts/list` / `prompts/get`
- `roots/list` の outbound request
- outbound `send-request` / `send-notification`
- progress notification と cancellation token

## 使い方

例:

```lisp
(defparameter *server*
  (mcp-sdk:make-server
   :name "example-server"
   :version "0.1.0"))

(mcp-sdk:register-tool
 *server*
 "echo"
 :description "Echo text"
 :handler #'(lambda (context arguments)
              (declare (ignore context))
              (let ((text (mcp-sdk:json-get arguments "text")))
                (mcp-sdk::make-object
                 "content"
                 (vector (mcp-sdk::make-object
                          "type" "text"
                          "text" text))))))

(mcp-sdk:start-server *server*)
```

## 使用例

使用例は [`examples/`](examples/) にあります。ASDF system は
[`mcp-sdk-examples.asd`](mcp-sdk-examples.asd) で定義しています。

- `mcp-sdk-examples/echo-server`
  最小構成の `echo` tool だけを持つサーバです。
- `mcp-sdk-examples/notes-server`
  `tools` / `resources` / `prompts` をまとめて試せるノート管理サーバです。

読み込み例:

```lisp
(require :asdf)
(asdf:load-asd #P"/path/to/cl-mcp-sdk/mcp-sdk-examples.asd")
(asdf:load-system "mcp-sdk-examples")
```

## 公開 API

### サーバ生成と起動

- `mcp-sdk:make-server &key name version transport (worker-count 2)`
  MCP サーバオブジェクトを生成します。
  `name` と `version` は `initialize` response の `serverInfo` に入ります。
  `transport` を省略した場合は `stdio` transport を使用します。
  `worker-count` は request 実行に使う `lparallel` worker 数です。
- `mcp-sdk:start-server server`
  transport の読み書きループと worker を起動します。
- `mcp-sdk:stop-server server`
  サーバを停止します。

### transport

- `mcp-sdk:make-stdio-transport &key (input *standard-input*) (output *standard-output*)`
  `stdio` transport を生成します。
  `input` から 1 行 1 JSON メッセージを読み、`output` に 1 行 1 JSON で書き出します。
- `mcp-sdk:<stdio-transport>`
  `stdio` transport のクラスです。
- `mcp-sdk:transport-send-message transport message`
  transport に JSON-RPC メッセージを送信します。
  `message` は JSON object 相当の hash-table を想定します。

### ツール登録

- `mcp-sdk:register-tool server name &key title description input-schema output-schema annotations handler`
  tool を登録します。
- `mcp-sdk:define-tool server name (context arguments) ...`
  `register-tool` の薄いマクロです。

- `name`
  tool 名です。`tools/list` と `tools/call` の識別子に使われます。
- `title`, `description`, `annotations`
  `tools/list` response にそのまま載るメタデータです。
- `input-schema`, `output-schema`
  JSON Schema 相当の JSON object を想定します。
  Common Lisp 側では hash-table / list / vector / scalar からなる JSON 風データを渡します。
  SDK はこの schema をそのまま `tools/list` response に載せるだけで、現時点では
  バリデーションは行いません。
- `handler`
  `#'(lambda (context arguments) ...)` の形で定義します。
  `arguments` は `tools/call` の `params.arguments` を表す JSON object 相当の hash-table です。
  返り値は `tools/call` response の `result` 全体としてそのまま返されます。
  典型的には `("content" [...])` を持つ object を返します。

例:

```lisp
(mcp-sdk:register-tool
 *server*
 "echo"
 :input-schema (mcp-sdk:json-decode "{\"type\":\"object\"}")
 :handler #'(lambda (context arguments)
              (declare (ignore context))
              (mcp-sdk::make-object
               "content"
               (vector (mcp-sdk::make-object
                        "type" "text"
                        "text" (mcp-sdk:json-get arguments "text"))))))
```

### リソース登録

- `mcp-sdk:register-resource server name &key uri uri-template description mime-type handler`
  resource を登録します。
- `mcp-sdk:define-resource server name (context arguments) ...`
  `register-resource` の薄いマクロです。

- `uri`, `uri-template`, `description`, `mime-type`
  resource のメタデータです。`uri` を指定した resource は `resources/list` に、
  `uri-template` を指定した resource は `resources/templates/list` にそのまま載ります。
- `handler`
  `#'(lambda (context params) ...)` の形で定義します。
  第 2 引数は `resources/read` の `params` 全体です。通常は `uri` を含みます。
  返り値は `resources/read` response の `result` 全体としてそのまま返されます。
  典型的には `("contents" [...])` を持つ object を返します。
  `uri-template` を指定した場合も、`resources/read` には実際に読みたい `uri` が渡されます。

### プロンプト登録

- `mcp-sdk:register-prompt server name &key description arguments handler`
  prompt を登録します。
- `mcp-sdk:define-prompt server name (context arguments) ...`
  `register-prompt` の薄いマクロです。

- `arguments`
  `prompts/list` response に載せる引数定義です。
  典型的には各要素が `name`、`description`、`required` などを持つ object の list です。
  SDK はこの定義をそのまま配列化して返すだけで、現時点では引数定義に基づく
  バリデーションは行いません。
- `handler`
  `#'(lambda (context arguments) ...)` の形で定義します。
  `arguments` は `prompts/get` の `params.arguments` を表す JSON object 相当の hash-table です。
  返り値は `prompts/get` response の `result` 全体としてそのまま返されます。
  典型的には `("messages" [...])` を持つ object を返します。

### request context

- `mcp-sdk:context-list-roots context &key timeout`
  クライアントへ `roots/list` request を送り、`roots` 配列を返します。
  client が `initialize` で `roots` capability を広告していない場合は
  `mcp-sdk:mcp-error` を送出します。
  `timeout` を指定した場合は `send-request` と同じ意味で待機時間を制限します。
- `mcp-sdk:context-report-progress context progress &optional total message`
  `notifications/progress` を送信します。
  `progress` は現在値、`total` は総量、`message` は進捗メッセージです。
  呼び出し元 request に progress token が無い場合は何もしません。
- `mcp-sdk:context-cancelled-p context`
  cancellation token が立っているかを返します。
  強制停止は行わないため、長時間処理では handler 側が協調的に確認する想定です。

### クライアントへの送信

- `mcp-sdk:send-request server method &key params timeout`
  サーバからクライアントへ request を送信し、response の `result` を返します。
  `params` は JSON object 相当の hash-table を想定します。
  response が `error` の場合は `mcp-sdk:mcp-error` を送出します。
  `timeout` が `nil` の場合は response が返るまで待機します。
- `mcp-sdk:send-notification server method &optional params`
  サーバからクライアントへ notification を送信します。
  `params` は省略可能で、指定した場合は `notification` の `params` にそのまま入ります。

### JSON ヘルパ

- `mcp-sdk:json-encode object`
  Lisp データを JSON 文字列に変換します。
- `mcp-sdk:json-decode string`
  JSON 文字列を hash-table 中心の Lisp データへ変換します。
- `mcp-sdk:json-get object key &optional default`
  JSON object / list / vector から値を取得します。`key` には文字列だけでなく、
  `("items" 0 "name")` のような path も指定できます。
  `default` を指定した場合、値が存在しなければそれを返します。
- `mcp-sdk:deep-copy-object object`
  JSON 風データを深くコピーします。

### イベント

- `mcp-sdk:server-on server event listener`
  サーバ内部イベントを購読します。
- `mcp-sdk:server-off server event listener`
  購読を解除します。

現在は少なくとも次のイベントを発火します。

- `:request-received`
- `:notification-received`
- `:response-sent`
- `:request-cancelled`
- `:progress-reported`
- `:handler-failed`
- `:server-started`
- `:server-stopped`

### 条件型

- `mcp-sdk:mcp-error`
  SDK 内部で使用する MCP エラー条件です。
- `mcp-sdk:mcp-error-code`
- `mcp-sdk:mcp-error-message`
- `mcp-sdk:mcp-error-data`

### 公開クラス

- `mcp-sdk:<server>`
- `mcp-sdk:<stdio-transport>`

## インストール

依存ライブラリ:

- `alexandria`
- `jonathan`
- `bordeaux-threads`
- `lparallel`
- `uiop`

`cl-event-emitter` は [`vendor/cl-event-emitter`](vendor/cl-event-emitter) に
vendor してあり、[`event-emitter.asd`](event-emitter.asd) によって
`event-emitter` という外部 ASDF system として公開しています。

テスト実行:

```lisp
(asdf:test-system "mcp-sdk")
```
