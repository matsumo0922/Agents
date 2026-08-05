# falsify

設計、提案、実装方針に対して、書いた本人以外の clean context が反例を探す独立反証スキルです。書き手の自己承認では見つからない欠陥を、実装に入る前に潰します。

## 使いどころ

- `/opsx:propose` で作った proposal + delta spec を、実装前に独立した視点で反証したいとき
- safety / security / migration / cross-layer に触れる設計の穴を、書き手と利害を共有しないエージェントに探させたいとき
- issue-pr-autopilot の反証ゲート（高リスク提案の必須通過点）として

## 設計の要点

- **clean context の falsifier**：反証対象とリポジトリ（読み取り専用）だけを渡し、書き手の弁明や検討の経緯を渡さない。Codex 環境では Codex 自身のサブエージェント（spawn）で立てる
- **モデルの既定**：Claude subagent を使える環境では Opus 5、GPT を使える環境では gpt-5.6-sol / high。高リスク基準（safety / security / migration / cross-layer 等）に触れる対象は、呼び出し側が spawn 前に 1 段上（Fable 5、または gpt-5.6-sol / xhigh）へ昇格します
- **反証 5 ベクトル**：production fact との不一致 / invariant を破る反例 / failure 後の downstream state / safety direction / 負荷、容量、upgrade path
- **blocking は自己承認で閉じられない**：設計修正、保証の縮退、stage-out、人間判断の 4 ルートのみで閉じ、解消確認は falsifier が行う
- **スコープ判定は ladder 基準**：受け入れ条件に紐付かない拡張の混入は、ponytail スキルの ladder（最小充足の 7 段）を基準に判定し、より上の段で足りる設計要素を反例として挙げます。ladder の正本は ponytail スキルで、呼び出し側が falsifier の brief に展開して渡します
- **高リスク未検証前提は fail-safe 仮決めで前進**：自走中に検証不能な高リスク前提に遭っても停止せず、fail-safe 側（既存状態を変更しない側）を仮決めし、（高リスク・要人間確認）マークと採らなかった選択肢の併記で可視化します。マークされた前提は reviewer の必須反証対象になります
- **価値判断はユーザー専権**：リスク許容や運用方針はユーザーに質問で確定させ、agent の判断は帰属タグ（ユーザー確認済み / agent 仮決め / 高リスク・要人間確認）で可視化する

dig との対称構造として、dig は設計前の対話反証（ユーザーと）を、falsify は設計後の独立反証（clean context）を担います。

## ファイル

- `SKILL.md`：スキル本体。発動判定、falsifier の職掌と反証 5 ベクトル、blocking の判定と処置、高リスク未検証前提のプロトコル、帰属タグと質問の作法を定義します。
- `agents/openai.yaml`：UI メタ情報です。

## リンク

リポジトリ root で以下を実行すると、`~/.claude/skills/falsify` と `~/.codex/skills/falsify` に symlink を作成できます。

```bash
make link
```
