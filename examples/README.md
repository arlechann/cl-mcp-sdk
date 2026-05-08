# 使用例

## echo-server

最小構成の MCP サーバです。`echo` tool だけを公開し、受け取った文字列をそのまま返します。

読み込み例:

```lisp
(require :asdf)
(asdf:load-system "mcp-sdk-examples/echo-server")
(mcp-sdk.examples.echo:main)
```

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
