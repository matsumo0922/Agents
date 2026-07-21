# CLIProxyAPI セットアップガイド

このドキュメントは、Claude Code から API 従量課金ではなく **ChatGPT / Claude のサブスク枠（OAuth）** 経由で GPT 系・Claude 系モデルを使うためのローカルプロキシ、[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) のセットアップ手順を記述する。

公式ドキュメントは [https://help.router-for.me/](https://help.router-for.me/) を参照する。日本語版は README_JA.md のみで手順は薄いため、本ガイドは日本語で手順を再構成したものである。

このガイドは私用プロキシのセットアップのみを扱う。業務環境や社内プロキシの構成は対象外である。

## 1. 全体像

CLIProxyAPI は、OAuth ログインしたサブスク枠を Anthropic / OpenAI 互換 API として再公開するローカルプロキシである。Claude Code は Anthropic API 形式（`/v1/messages`）でこのプロキシに接続し、プロキシが OAuth 済みの各プロバイダへリクエストを中継する。

```text
Claude Code ──(Anthropic API 形式 /v1/messages)──▶ CLIProxyAPI (127.0.0.1:8317) ──(OAuth/サブスク枠)──▶ ChatGPT(GPT系) / Claude
```

GPT のサブスクで Claude が使えるわけではない。使いたいプロバイダごとに個別に OAuth ログインが必要である（GPT は `-codex-login`、Claude は `-claude-login`）。

## 2. インストール

Homebrew でインストールする。

```bash
brew install cliproxyapi
```

バイナリ名は `cliproxyapi`（`cli-proxy-api` ではない）。デフォルトの設定パスは Apple Silicon 環境で `/opt/homebrew/etc/cliproxyapi.conf` であり、`brew services` で常駐させる場合はこのパスが読まれる。

### 設定を `~/.cli-proxy-api/config.yaml` に集約する

公式の Quick Start が推奨する方式として、OAuth トークンの保存先（`auth-dir`）と設定ファイルを同じディレクトリにまとめる。そのために Homebrew 側の設定パスを、実体を置くディレクトリへの symlink に張り替える。

```bash
brew_conf="$(brew --prefix)/etc/cliproxyapi.conf"
home_conf="$HOME/.cli-proxy-api/config.yaml"

brew services stop cliproxyapi
mkdir -p "$HOME/.cli-proxy-api"
cp "$brew_conf" "$home_conf"                              # brew 側の雛形をコピー
mv "$brew_conf" "${brew_conf}.bak.$(date +%Y%m%d-%H%M%S)" # 元をバックアップ
ln -sfn "$home_conf" "$brew_conf"                         # symlink 張り替え
```

結果として `/opt/homebrew/etc/cliproxyapi.conf` は `~/.cli-proxy-api/config.yaml` への symlink になる。

**注意**: symlink のリンク先は、サービス起動前に必ず実在させること。リンク先が存在しない dangling symlink の状態で `brew services start` すると、サービスは即座に終了する。上記の手順のように、symlink を張る前に `cp` で実体ファイルを作成してから `ln -sfn` する順序を守る。

## 3. 設定ファイルの要点

`~/.cli-proxy-api/config.yaml` の主要な項目は次のとおりである。

```yaml
host: "127.0.0.1"   # ローカル専用。初期値 "" は全 NIC 待受になるため変更する
port: 8317           # 固定値。システムが動的に変えることはない
auth-dir: "~/.cli-proxy-api"
api-keys:
  - "<your-api-key>"  # openssl rand -hex 24 で生成したローカル専用の鍵
```

- `host: "127.0.0.1"` にする理由: 初期値の `""` は全ネットワークインターフェースで待ち受けるため、LAN 内の他デバイスからアクセスできてしまう。ローカル専用にするため明示的に指定する。
- `port` は固定値である。`.zshrc` などにポート番号をベタ書きしても問題ない。
- `api-keys` に登録した値が、Claude Code からこのプロキシへ接続する際の認証鍵になる。値は次のコマンドで生成する。

```bash
openssl rand -hex 24
```

生成した値を `api-keys` に追記し、後述の Claude Code 側の環境変数にも同じ値を設定する。

## 4. OAuth ログイン

使いたいプロバイダごとに、ブラウザでの OAuth 認証が必要である。

```bash
cliproxyapi -codex-login    # GPT（ChatGPT サブスク）。ヘッドレス環境では -codex-device-login
cliproxyapi -claude-login   # Claude（Claude サブスク）
```

その他のプロバイダ向けログインフラグとして `-antigravity-login`（Gemini）、`-kimi-login`、`-xai-login` がある。

ログインに成功すると、トークンが `auth-dir`（既定では `~/.cli-proxy-api`）配下にプロバイダごとのファイルとして保存される。ファイル名は次のようなパターンになる。

- `codex-<id>-<mail>-<plan>.json`（ChatGPT。`<plan>` はアカウントのプラン種別）
- `claude-<mail>.json`

これらのファイルには認証情報が含まれるため、コミットや共有をしない。

## 5. サービス起動と疎通確認

`brew services` で launchd 常駐として運用する。

```bash
brew services start cliproxyapi    # 常駐開始（ログイン時自動起動、落ちても再起動）
brew services restart cliproxyapi  # 設定変更・アップグレード後の反映
brew services stop cliproxyapi     # 停止＋自動起動解除
```

自動起動をやめて手動運用にしたい場合は `brew services stop` した後、使うときだけ次のコマンドを前面実行する。

```bash
cliproxyapi -config ~/.cli-proxy-api/config.yaml
```

疎通確認は、ポートが待ち受けていることの確認と、API 経由でのモデル一覧取得の 2 段階で行う。

```bash
# 127.0.0.1:8317 で LISTEN しているか確認する
lsof -iTCP:8317 -sTCP:LISTEN -n -P

# モデル一覧を取得する（<your-api-key> は config.yaml の api-keys の値）
curl -s http://127.0.0.1:8317/v1/models -H "Authorization: Bearer <your-api-key>"
```

`/v1/models` が正常応答すれば、OAuth ログイン済みの Claude 系・GPT 系モデルが一覧に含まれる。

## 6. Claude Code からの利用

Claude Code から CLIProxyAPI に接続するには、`ANTHROPIC_BASE_URL` にプロキシのアドレスを、`ANTHROPIC_AUTH_TOKEN` に `api-keys` へ登録した値を設定する。認証方式は `ANTHROPIC_AUTH_TOKEN`（`Authorization: Bearer` ヘッダとして送られる）を使う。`ANTHROPIC_API_KEY` とは別の環境変数であり、両方が同時に設定されていると挙動が不安定になるため、プロキシ経由で起動する際は `ANTHROPIC_API_KEY` を明示的に `unset` する。

シェル関数として定義し、サブシェルで環境変数のスコープを閉じる例を示す。

```bash
cliproxy-claude() {
  (
    export ANTHROPIC_BASE_URL=http://127.0.0.1:8317
    export ANTHROPIC_AUTH_TOKEN=<your-api-key>
    unset ANTHROPIC_API_KEY
    claude --permission-mode auto "$@"
  )
}
```

`( ... )` によるサブシェルでくくることで、環境変数の変更はこの関数呼び出しの中だけに閉じ、他のシェルやプロキシを使わない別の Claude Code 起動方法に影響しない。関数への引数はすべて `"$@"` で `claude` コマンドに透過する。

### custom API key の確認プロンプトについて

`ANTHROPIC_API_KEY` を環境変数として持った状態で Claude Code を起動すると、「Detected a custom API key … use this key?」という確認プロンプトが出ることがある。`ANTHROPIC_AUTH_TOKEN` 方式に統一していれば、通常このプロンプトは発生しない。

もし発生した場合の挙動は次のとおりである。

- 承認状態は `~/.claude.json` の `customApiKeyResponses.approved` / `.rejected` 配列に、鍵の末尾 20 文字をキーとして保存される。
- プロンプトで `1. Yes` を選ぶと `approved` に入り、以降は聞かれなくなる。誤って `No` を選ぶと `rejected` に入り、API エラーになる。この場合は `~/.claude.json` を編集し、該当のキーを `rejected` から `approved` へ手動で移す。
- 環境変数でこのプロンプト自体をスキップする方法は用意されていない。

## 7. モデル指定

CLIProxyAPI 経由（`ANTHROPIC_BASE_URL` が Anthropic 公式以外を指している状態）では、Claude Code はモデル ID を検証せずそのままプロキシへ送る。モデル ID の検証は Anthropic API に直接接続している場合のみ行われる。

このため、対話中に `/model` コマンドや `--model` フラグで、Claude 系以外の任意のモデル名を指定できる。

```text
/model gpt-5.6-sol(high)
```

`settings.json` の `"model"` にフル ID を指定する場合も同様に通る。

### reasoning effort の括弧記法

CLIProxyAPI の thinking 機能により、モデル名に括弧でレベルまたは数値予算を付けると reasoning effort を制御できる。詳細は公式ドキュメント（[https://help.router-for.me/configuration/thinking](https://help.router-for.me/configuration/thinking)）を参照する。

```text
gpt-5.6-sol(high)
```

プロキシがこの括弧を解釈し、upstream プロバイダの reasoning 制御（OpenAI/Codex/OpenRouter の `reasoning.effort`、または Gemini/Claude の thinking budget）に変換する。

有効なレベルはモデルごとに異なる。`gpt-5.6-sol` の場合は `low` / `medium` / `high` / `xhigh` / `max` が有効である。無効なレベル（例: `minimal`）を指定すると、CLIProxyAPI は HTTP 400 エラーを返す。一方、レベルとして解釈できない無効な文字列を括弧内に書いた場合は、括弧ごと無視され、デフォルトの effort で正常応答が返る。効果を検証する際は、この 2 パターンの違い（エラー応答か、括弧が無視されただけの正常応答か）を取り違えないよう注意する。

Claude Code の `settings.json` の `effortLevel` は Anthropic ネイティブモデル用の設定であり、プロキシ経由の GPT 系モデルには効かない。GPT 系モデルの effort は、モデル名の括弧記法が唯一の制御点である。

effort の効果を検証する際は、タイムアウトやエラー応答を根拠にしない。ハングとの区別がつかないためである。`status=completed` かつ `incomplete=None` の正常完了レスポンスを複数回比較し、reasoning のトークン数や所要時間の分布で判断する。十分に難しい問題でなければ、medium 以上で効果が頭打ちになり差が見えないことがある。

## 8. subagent での GPT 利用

Claude Code の Task（Agent）ツールが受け取る `model` パラメータは、`sonnet` / `opus` / `haiku` / `fable` の Claude alias に限定された enum であり、`gpt-5.6-sol` のような GPT のモデル名を直接渡すことはできない。また Task ツールに `effort` 引数は存在しない。そのため、呼び出し元（main エージェント）がタスク実行時にモデルや effort を動的に指定して GPT の subagent を起動することはできない。

この制約を回避する唯一の実用的な方法は、`.claude/agents/*.md` の agent 定義ファイルの frontmatter に `model:` と `effort:` を明示することである。frontmatter の `model:` は enum 制限のないフリーテキストであり、GPT のモデル名を直接書ける。

```yaml
---
name: gpt-high
description: gpt-5.6-sol を high effort で実行する汎用ワーカー。
model: gpt-5.6-sol
effort: high
---
```

この方式では、model と effort の組み合わせごとに agent ファイルを 1 枚作成し、main エージェントは用途に応じて agent 名で呼び分ける。effort の段階を増減したい場合は、対応する agent ファイルを追加・削除するだけでよい。

Claude 系モデル（opus / sonnet / haiku / fable）は標準の alias enum に含まれているため、agent 定義ファイルを用意する必要はなく、main エージェントが Task の `model:` パラメータで直接指定できる。agent ファイルが必要になるのは enum に含まれない GPT 系モデルのみである。

本リポジトリで配布している GPT worker agent 定義（`agents/gpt-medium.md` / `agents/gpt-high.md` / `agents/gpt-xhigh.md`）は、この方式の実装例である。配布方法は [README.md](../README.md) の「agent 定義（GPT worker）の運用」を参照する。

### 多段 subagent の返信経路

main から GPT worker を Agent tool で起動するときは、各インスタンスに一意な `name` を指定する。中間の GPT worker に `name` がないと、子に通知される `teammate_id` が `gpt-high` などの agent type ラベルになる。このラベルは `SendMessage` の返信先として解決できないため、子の処理が完了しても結果を中間 worker が受け取れない。

一意な `name` で起動された GPT worker は teammate になる。team roster は flat であり、teammate はさらに `name` 付き teammate を起動できない。多段委譲では child Agent の `name` を省略し、`run_in_background: false` の同期 subagent として起動して、Agent の戻り値から結果を回収する。nested teammate、background agent、`SendMessage` の返信による結果回収は使用しない。

この制約は Claude Code の Agent / `SendMessage` におけるインスタンス名の解決規則であり、CLIProxyAPI の API 中継や GPT モデル自体の制約ではない。

## 9. frontmatter `effort` の注意

agent 定義ファイルの frontmatter にある `effort` フィールドは、本来 Anthropic ネイティブの thinking 機能向けのオプションである。プロキシ経由で GPT 系モデルを使う場合は、この値が文字列としてそのまま CLIProxyAPI に渡り、CLIProxyAPI 側で `reasoning_effort` に変換されることで結果的に機能している。

この経路は Claude Code 本来の想定用途ではないため、Claude Code のバージョンアップ時に `effort` の扱いが変わる可能性がある。バージョンアップ後は、実タスクを実行して reasoning の深さ（tool 使用回数や所要時間、成果物の網羅性の違いなど）に有意な差が出るかを再検証する。検証の際は、タイムアウトやエラー応答を効果の根拠にせず、正常完了したレスポンスを複数回比較して判断する。
