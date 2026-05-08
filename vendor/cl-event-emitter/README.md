# cl-event-emitter

`cl-event-emitter` は Common Lisp 向けの小さなイベントエミッタライブラリです。
リスナの登録、解除、イベント発火を行うための最小限の API を提供します。

## 特徴

- API は `on` / `off` / `emit` / `once` に絞った最小構成
- 互換的な別名として `add-listener` / `remove-listener` を提供
- `make-event-emitter` で単体利用できる
- `<event-emitter>` を継承して自前クラスへ組み込める

## インストール

このリポジトリを ASDF から見える場所に配置して、読み込みます。

```lisp
(asdf:load-system "event-emitter")
```

## 使い方

```lisp
(defpackage #:my-app
  (:use #:cl)
  (:import-from #:event-emitter
                #:make-event-emitter
                #:on
                #:emit
                #:once
                #:off))

(in-package #:my-app)

(let ((emitter (make-event-emitter)))
  (on emitter :message
      (lambda (text)
        (format t "message: ~A~%" text)))

  (once emitter :connected
        (lambda ()
          (format t "connected once~%")))

  (emit emitter :message "hello")
  (emit emitter :connected)
  (emit emitter :connected))
```

上の例では、`:message` に登録したリスナへ文字列を渡して発火し、
`:connected` については `once` により最初の 1 回だけ実行します。

## 継承して使う

`<event-emitter>` を継承すると、イベントエミッタとしての振る舞いを
自前のクラスに直接持たせられます。

```lisp
(defpackage #:my-domain
  (:use #:cl)
  (:import-from #:event-emitter
                #:<event-emitter>
                #:on
                #:emit))

(in-package #:my-domain)

(defclass user-session (<event-emitter>)
  ((user-id :initarg :user-id
            :reader user-id)))

(let ((session (make-instance 'user-session :user-id 10)))
  (on session :closed
      (lambda ()
        (format t "session ~A closed~%" (user-id session))))
  (emit session :closed))
```

## API

### `make-event-emitter`

新しいイベントエミッタインスタンスを生成して返します。

### `on emitter event listener`

`event` に対して `listener` を登録します。
戻り値は登録したリスナ関数です。

### `off emitter event listener`

`event` から `listener` を解除します。
戻り値は渡したリスナ関数です。

### `emit emitter event &rest args`

`event` に登録されているすべてのリスナを呼び出します。
`args` は各リスナにそのまま渡されます。
戻り値は `event` です。

### `once emitter event listener`

最初の 1 回だけ実行されるリスナを登録します。
内部で使われるラッパー関数を返すため、初回発火前であれば `off` で解除できます。

```lisp
(let* ((emitter (make-event-emitter))
       (token (once emitter :ready (lambda () (format t "ready~%")))))
  (off emitter :ready token))
```

### `add-listener` / `remove-listener`

それぞれ `on` / `off` の別名です。

## 注意点

- イベントキーは `eq` 比較のハッシュテーブルで管理されます。
  そのため、イベント識別子にはシンボルやキーワードを使うのが安全です。
- 同じイベントに複数のリスナを登録した場合、呼び出し順は登録の逆順です。
- リスナ解除にも `eq` を使うため、登録時と同じ関数オブジェクトを渡す必要があります。

## テスト実行

```lisp
(asdf:test-system "event-emitter")
```

## ライセンス

CC0-1.0
