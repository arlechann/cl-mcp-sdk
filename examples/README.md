# 使用例

## echo-server

最小構成の MCP サーバです。`echo` tool だけを公開し、受け取った文字列をそのまま返します。

読み込み例:

```lisp
(require :asdf)
(asdf:load-system "mcp-sdk-examples/echo-server")
(mcp-sdk.examples.echo:main)
```

[MCP Inspector](https://github.com/modelcontextprotocol/inspector) で確認するには次を使います。

```sh
./examples/run-echo-server-inspector.sh
```

第 1 引数に bind する IP アドレス、第 2 引数に Inspector のポートを指定できます。
未指定時は `127.0.0.1` と `6274` を使います。

## notes-server

メモリ上のノートを扱う MCP サーバです。次をまとめて確認できます。

- `tools`: `notes/create` `notes/list` `notes/get` `notes/delete`
- `resources`: `note://index` `note://latest`
- `prompts`: `summarize-notes` `rewrite-note`

読み込み例:

```lisp
(require :asdf)
(asdf:load-system "mcp-sdk-examples/notes-server")
(mcp-sdk.examples.notes:main)
```

[MCP Inspector](https://github.com/modelcontextprotocol/inspector) で確認するには次を使います。

```sh
./examples/run-notes-server-inspector.sh
```

第 1 引数に bind する IP アドレス、第 2 引数に Inspector のポートを指定できます。
未指定時は `127.0.0.1` と `6274` を使います。
