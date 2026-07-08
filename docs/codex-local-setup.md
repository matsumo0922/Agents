# Codex ローカルセットアップ

このドキュメントは、scripts で自動化しない Codex の個人環境設定を置く場所です。`~/.codex/config.toml`、sandbox の writable root、cache の配置、絶対パスは PC ごとに変わるため、このリポジトリの scripts は自動編集しません。

公開リポジトリに入る内容なので、secret、API key、credential の値は書きません。個人用 cache や認証ファイルもコミットしません。

## Gradle cache

Codex sandbox 内で Gradle を実行する環境では、Gradle の user home を writable root 配下に置きます。Gradle は dependency cache や wrapper の配布物を user home に書き込むため、sandbox から書き込み可能な場所を指定すると `make test` や `make detekt` 経由の Gradle 実行にも同じ設定が効きます。

まず cache directory を作成します。パスは自分の Codex writable root 配下に合わせます。

```bash
mkdir -p ~/dev/App/.codex-gradle-home
```

`~/.codex/config.toml` に `shell_environment_policy.set.GRADLE_USER_HOME` を設定します。`GRADLE_USER_HOME` には、使用する PC の絶対パスを指定します。

```toml
[shell_environment_policy]
inherit = "all"

[shell_environment_policy.set]
GRADLE_USER_HOME = "/Users/<user>/dev/App/.codex-gradle-home"
```

既に `[shell_environment_policy]` や `[shell_environment_policy.set]` がある場合は、既存の設定に `GRADLE_USER_HOME` だけを追加します。同じ table を重複して書きません。

Codex は起動時の設定を使うため、`~/.codex/config.toml` を編集した後は Codex を開き直すか、resume し直します。

`.codex-gradle-home` は個人用 cache です。破損した場合や容量を空ける場合は削除できます。次回の Gradle 実行で必要な内容が再取得されます。
