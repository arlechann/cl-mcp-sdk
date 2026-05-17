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
- `completion/complete`
- `logging/setLevel`
- `tasks/get` / `tasks/result` / `tasks/list` / `tasks/cancel`
- roots capability を使った roots cache の同期
- outbound `send-request` / `send-notification`
- `notifications/message` / progress notification と cancellation token

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
 :handler #'(lambda (session context arguments)
              (declare (ignore session context))
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
  `tools` / `resources` / `prompts` / `tasks` をまとめて試せるノート管理サーバです。

読み込み例:

```lisp
(require :asdf)
(asdf:load-asd #P"/path/to/cl-mcp-sdk/mcp-sdk-examples.asd")
(asdf:load-system "mcp-sdk-examples")
```

## 公開 API

### サーバ生成と起動

- `mcp-sdk:make-server &key name version transport (worker-count 2) task-default-ttl-ms task-max-ttl-ms task-poll-interval-ms task-list-page-size task-max-count`
  MCP サーバオブジェクトを生成します。
  `name` と `version` は `initialize` response の `serverInfo` に入ります。
  `transport` を省略した場合は `stdio` transport を使用します。
  生成された `server` は tool / resource / prompt の定義と transport を保持します。
  `worker-count` は request 実行に使う `lparallel` worker 数です。
  `task-default-ttl-ms` は task request に `ttl` 指定が無い場合の既定 TTL、
  `task-max-ttl-ms` は受け付ける最大 TTL、
  `task-poll-interval-ms` は task object に載せる polling 間隔、
  `task-list-page-size` は `tasks/list` の既定ページサイズ、
  `task-max-count` は保持する task 件数上限です。
- `mcp-sdk:start-server server`
  transport の読み書きループと worker を起動します。
  `stdio` transport では起動時に 1 つの `session` が作られます。
- `mcp-sdk:stop-server server`
  サーバを停止します。
- `mcp-sdk:make-session server`
  `server` に紐づく `session` を生成します。
  `handle-message`、`send-request`、`send-notification`、`current-roots`、
  `log-message` などの runtime API は `session` に対して呼びます。

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

- `mcp-sdk:register-tool server name &key title description input-schema output-schema annotations handler task-support`
  tool を登録します。
- `mcp-sdk:define-tool server name (session context arguments) ...`
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
  `#'(lambda (session context arguments) ...)` の形で定義します。
  `session` は接続単位の状態、`context` は request 単位の状態です。
  `arguments` は `tools/call` の `params.arguments` を表す JSON object 相当の hash-table です。
  返り値は `tools/call` response の `result` 全体としてそのまま返されます。
  典型的には `("content" [...])` を持つ object を返します。
- `task-support`
  tool の task 対応方針です。`"forbidden"` / `"optional"` / `"required"`、
  または対応する keyword を受け付けます。
  `tools/list` では `execution.taskSupport` として返されます。
  `"required"` の tool は task 付き `tools/call` でのみ呼べます。

例:

```lisp
(mcp-sdk:register-tool
 *server*
 "echo"
 :input-schema (mcp-sdk:json-decode "{\"type\":\"object\"}")
 :handler #'(lambda (session context arguments)
              (declare (ignore session context))
              (mcp-sdk::make-object
               "content"
               (vector (mcp-sdk::make-object
                        "type" "text"
                        "text" (mcp-sdk:json-get arguments "text"))))))
```

### リソース登録

- `mcp-sdk:register-resource server name &key uri uri-template description mime-type handler completion-handler`
  resource を登録します。
- `mcp-sdk:define-resource server name (session context arguments) ...`
  `register-resource` の薄いマクロです。

- `uri`, `uri-template`, `description`, `mime-type`
  resource のメタデータです。`uri` を指定した resource は `resources/list` に、
  `uri-template` を指定した resource は `resources/templates/list` にそのまま載ります。
- `handler`
  `#'(lambda (session context params) ...)` の形で定義します。
  第 3 引数は `resources/read` の `params` 全体です。通常は `uri` を含みます。
  返り値は `resources/read` response の `result` 全体としてそのまま返されます。
  典型的には `("contents" [...])` を持つ object を返します。
  `uri-template` を指定した場合も、`resources/read` には実際に読みたい `uri` が渡されます。
- `completion-handler`
  `#'(lambda (session context argument context-arguments) ...)` の形で定義します。
  `completion/complete` で `ref/resource` として参照されたときに呼ばれます。
  返り値は `values` / `total` / `hasMore` を持つ object、または候補文字列の list / vector を想定します。

### プロンプト登録

- `mcp-sdk:register-prompt server name &key description arguments handler completion-handler`
  prompt を登録します。
- `mcp-sdk:define-prompt server name (session context arguments) ...`
  `register-prompt` の薄いマクロです。

- `arguments`
  `prompts/list` response に載せる引数定義です。
  典型的には各要素が `name`、`description`、`required` などを持つ object の list です。
  SDK はこの定義をそのまま配列化して返すだけで、現時点では引数定義に基づく
  バリデーションは行いません。
- `handler`
  `#'(lambda (session context arguments) ...)` の形で定義します。
  `arguments` は `prompts/get` の `params.arguments` を表す JSON object 相当の hash-table です。
  返り値は `prompts/get` response の `result` 全体としてそのまま返されます。
  典型的には `("messages" [...])` を持つ object を返します。
- `completion-handler`
  `#'(lambda (session context argument context-arguments) ...)` の形で定義します。
  `completion/complete` で `ref/prompt` として参照されたときに呼ばれます。
  返り値は `values` / `total` / `hasMore` を持つ object、または候補文字列の list / vector を想定します。

### request context

- `mcp-sdk:context-report-progress context progress &optional total message`
  `notifications/progress` を送信します。
  `progress` は現在値、`total` は総量、`message` は進捗メッセージです。
  呼び出し元 request に progress token が無い場合は何もしません。
- `mcp-sdk:context-cancelled-p context`
  cancellation token が立っているかを返します。
  強制停止は行わないため、長時間処理では handler 側が協調的に確認する想定です。

### roots

- `mcp-sdk:current-roots session`
  `session` にキャッシュされた現在の roots を返します。返り値は深いコピーです。
  roots cache は client が `roots` capability を広告している場合に、
  `notifications/initialized` と `notifications/roots/list_changed` を契機として
  `roots/list` を再取得して更新されます。

### tasks

- `tools/call` の `params.task`
  tool request を非同期 task として作成します。tool が `task-support` を
  `"optional"` または `"required"` として登録されている必要があります。
- `tasks/get`
  task object を返します。`taskId` を受け取り、現在の `status`、作成時刻、
  更新時刻、TTL などを返します。
- `tasks/result`
  task 完了まで待機し、完了後の result または error を返します。
  成功時の response には `_meta.io.modelcontextprotocol/related-task.taskId` を付けます。
- `tasks/list`
  新しい task から順に返します。`cursor` と `nextCursor` を使ったページングに対応します。
- `tasks/cancel`
  task の cancellation token を立て、`status` を `cancelled` に遷移させます。

### クライアントへの送信

- `mcp-sdk:send-request session method &key params timeout`
  サーバからクライアントへ request を送信し、response の `result` を返します。
  `params` は JSON object 相当の hash-table を想定します。
  response が `error` の場合は `mcp-sdk:mcp-error` を送出します。
  `timeout` が `nil` の場合は response が返るまで待機します。
- `mcp-sdk:send-notification session method &optional params`
  サーバからクライアントへ notification を送信します。
  `params` は省略可能で、指定した場合は `notification` の `params` にそのまま入ります。

### logging

- `mcp-sdk:log-message session level data &key logger`
  クライアントへ `notifications/message` を送ります。
  `level` は `"debug"` / `"info"` / `"notice"` / `"warning"` / `"error"` /
  `"critical"` / `"alert"` / `"emergency"`、または対応する keyword を受け付けます。
  `data` には JSON serializable な値をそのまま渡します。
  `logger` は任意の logger 名です。
  実際に通知が送信されるのは、クライアントが `logging/setLevel` で最低ログレベルを
  設定した後だけです。

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
- `mcp-sdk:session-on session event listener`
  `session` 単位の runtime event を購読します。
- `mcp-sdk:session-off session event listener`
  購読を解除します。

現在は少なくとも次のイベントを発火します。

- `:request-received`
- `:notification-received`
- `:response-sent`
- `:request-cancelled`
- `:progress-reported`
- `:log-message`
- `:task-created`
- `:task-completed`
- `:task-failed`
- `:task-cancelled`
- `:task-expired`
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

- `mcp-sdk:<session>`
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
