# lint テンプレート

Kotlin / Jetpack Compose プロジェクト共通の静的解析設定テンプレート。`rules/kotlin.md` の規約のうち、機械的に判定できるものをここで強制する。判断を伴う規約は `rules/kotlin.md` 本文が扱う。

## ファイル

- `detekt.yml`: detekt 設定。各プロジェクトの `config/detekt/detekt.yml` へコピーして使う
- `.editorconfig`: IDE フォーマッタ向けの trailing comma 設定。プロジェクト root の `.editorconfig` へ内容を取り込む

## 導入

`gradle/libs.versions.toml`:

```toml
[versions]
detekt = "1.23.8"
composeRules = "0.4.23"

[libraries]
detekt-formatting = { group = "io.gitlab.arturbosch.detekt", name = "detekt-formatting", version.ref = "detekt" }
compose-rules-detekt = { module = "io.nlopez.compose.rules:detekt", version.ref = "composeRules" }

[plugins]
detekt = { id = "io.gitlab.arturbosch.detekt", version.ref = "detekt" }
```

`build.gradle.kts`:

```kotlin
dependencies {
    detektPlugins(libs.detekt.formatting)
    detektPlugins(libs.compose.rules.detekt)
}
```

## バージョン制約

- この設定は detekt **1.23 系**を前提とする。detekt 2.0 は alpha のため対象外
- compose-rules は **0.4.23 まで**が detekt 1.23.8 対応。**0.5.0 以降は detekt 2.x 専用**のため、detekt を上げずに compose-rules だけ上げると動かない
- 互換表: https://mrmans0n.github.io/compose-rules/detekt/

## 初回導入時の確認

テンプレートの閾値は規約から導いた初期値のため、導入プロジェクトで一度 `./gradlew detekt` を実行して検出量を確認し、必要なら調整する。

- `MaxChainedCallsOnSameLine: 2`: 「チェーン2呼び出しまで1行」の境界が意図どおりか、既存コードの検出結果で確認する
- `ComplexCondition: 3`: 「論理演算子2つ以上で切り出し」の境界に対応する
- `complexity` 系（`LongMethod` / `LargeClass` / `TooManyFunctions` など）: デフォルト閾値で運用開始し、ノイズが多いルールは閾値を緩めるか除外を追加する
- `UnsafeCallOnNullableType` と `TooGenericExceptionCaught`: 現在は無効。検出量を確認の上、有効化を検討する

## rules/kotlin.md との対応

| 規約 | 強制するルール |
|---|---|
| trailing comma 必須 | `TrailingCommaOnDeclarationSite` / `TrailingCommaOnCallSite` |
| チェーン2呼び出しまで1行 | `MaxChainedCallsOnSameLine` |
| 一文字変数の禁止 | `VariableMinLength` |
| 論理演算子2つ以上の条件式禁止 | `ComplexCondition` |
| 引数3つ以上の定義は複数行 | `FunctionSignature` |
| Composable の modifier 引数 | `ModifierMissing` / `ModifierWithoutDefault` / `ComposableParamOrder` |
| ラムダ引数名は現在形 | `ParameterNaming` |
| Immutable なコレクション型 | `UnstableCollections` |
