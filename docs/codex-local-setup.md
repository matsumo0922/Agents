# Codex ローカルセットアップ

このドキュメントは、scripts で自動化しない Codex の個人環境設定を置く場所です。`~/.codex/config.toml`、sandbox の writable root、cache の配置、絶対パスは PC ごとに変わるため、このリポジトリの scripts は自動編集しません。

公開リポジトリに入る内容なので、secret、API key、credential の値は書きません。個人用 cache や認証ファイルもコミットしません。

## Claude bridge の Auto-review 設定

Codex から `claude-rescue` の `claude-bridge.sh` を実行すると、repository source、diff、設計・review 文脈を Anthropic Claude へ送信します。`approval_policy = "on-request"` と `approvals_reviewer = "auto_review"` を使う環境では、この送信が未登録の外部 destination への data export と判定され、`require_escalated` の実行が拒否される場合があります。

この repository と Anthropic への送信を信頼し、bridge 実行ごとの Auto-review を省略する場合は、`~/.codex/rules/default.rules` に bridge executable だけを許可する narrow prefix rule を追加します。この設定により、bridge 経由では repository source、diff、設計・review 文脈が今後の個別確認なしで Anthropic へ送信されます。secret、credential、認証ファイルを instruction や参照対象に含めない運用を前提とします。

まず、Agents checkout にある bridge の絶対パスを取得します。

```bash
realpath skills/claude-rescue/scripts/claude-bridge.sh
```

出力された絶対パスを `pattern` に指定します。次の `/absolute/path/to/Agents` は実際の checkout path に置き換えます。

```python
prefix_rule(
    pattern = [
        "/absolute/path/to/Agents/skills/claude-rescue/scripts/claude-bridge.sh",
    ],
    decision = "allow",
    justification = "Allow the owner-approved Claude review bridge without repeated Auto-review prompts.",
)
```

bridge executable だけを prefix にすることで、ほかの external command、destination、destructive operation は通常の sandbox と Auto-review の対象に保ちます。`approval_policy = "never"` や `sandbox_mode = "danger-full-access"` への変更は不要です。

rule の構文と match は、bridge を実行せずに確認できます。

```bash
BRIDGE="$(realpath skills/claude-rescue/scripts/claude-bridge.sh)"
codex execpolicy check --pretty \
  --rules ~/.codex/rules/default.rules \
  "$BRIDGE" /tmp/example-review.txt \
  --model claude-opus-4-8 --effort high --expect review_result
```

結果の `decision` が `allow` で、`matchedPrefix` が bridge の絶対パスなら rule は一致しています。

実際の無承認起動を確認する場合は、repository data を参照しない instruction で単発の疎通テストを行います。

```bash
cat >/tmp/claude-bridge-permission-test.txt <<'EOF'
ファイルや repository を読まず、外部 tool も使わず、次の形式だけを返してください。
<bridge_test>ok</bridge_test>
EOF

"$BRIDGE" /tmp/claude-bridge-permission-test.txt \
  --model claude-opus-4-8 --effort high --expect bridge_test
```

exit code `0` で `<bridge_test>ok</bridge_test>` が返り、Codex の approval が発生しなければ設定は有効です。単発呼び出しは通常 sandbox でも実行できます。`--resume` を使う処理は `~/.claude/projects` への書き込みが必要なため、skill の指示どおり `require_escalated` で起動しますが、この prefix rule に一致すれば個別の Auto-review は発生しません。

Codex は起動時に rule を読み込むため、`default.rules` を編集した後は Codex を開き直すか、新しい session を開始します。

## Gradle cache

Codex sandbox 内で Gradle を実行する環境では、Gradle の user home を writable root 配下に置きます。Gradle は dependency cache や wrapper の配布物を user home に書き込むため、sandbox から書き込み可能な場所を指定すると `make test` や `make detekt` 経由の Gradle 実行にも同じ設定が効きます。

まず `~/.codex/config.toml` の `[sandbox_workspace_write].writable_roots` を確認します。この値が、Codex の `workspace-write` sandbox から書き込み可能な追加 root です。

```toml
[sandbox_workspace_write]
writable_roots = ["~/dev"]
```

`~/dev` は例です。使用する PC に合わせて、実在する作業ディレクトリを writable root にします。Gradle user home は、その writable root 配下に実体ディレクトリとして作成します。Codex sandbox は `.codex`、`.agents`、`.git` などの agent metadata directory を、親ディレクトリが writable root でも読み取り専用として扱うため、Gradle user home はそれらの配下に置きません。

```bash
mkdir -p ~/dev/.codex-gradle-home
```

`~/.codex/config.toml` に `shell_environment_policy.set.GRADLE_USER_HOME` を設定します。`GRADLE_USER_HOME` には、使用する PC の絶対パスを指定します。

```toml
[shell_environment_policy]
inherit = "all"

[shell_environment_policy.set]
GRADLE_USER_HOME = "/Users/<user>/dev/.codex-gradle-home"
```

既に `[shell_environment_policy]` や `[shell_environment_policy.set]` がある場合は、既存の設定に `GRADLE_USER_HOME` だけを追加します。同じ table を重複して書きません。

`GRADLE_USER_HOME` の配置先は実体ディレクトリにします。writable root 配下に symlink を置いて `~/.gradle` を指す構成では、sandbox が symlink の解決先への書き込みを止めるため、`~/.gradle` の lock file 問題を回避できません。

Codex は起動時の設定を使うため、`~/.codex/config.toml` を編集した後は Codex を開き直すか、resume し直します。

Codex 用 Gradle user home は個人用 cache です。破損した場合や容量を空ける場合は削除できます。次回の Gradle 実行で必要な内容が再取得されます。
