# falsify

設計、提案、実装方針に対して、書いた本人以外の clean context が反例を探す独立反証スキルです。書き手の自己承認では見つからない欠陥を、実装に入る前に潰します。

## 使いどころ

- `/opsx:propose` で作った proposal + delta spec を、実装前に独立した視点で反証したいとき
- safety / security / migration / cross-layer に触れる設計の穴を、書き手と利害を共有しないエージェントに探させたいとき
- issue-pr-autopilot の反証ゲート（高リスク提案の必須通過点）として

## 設計の要点

- **clean context の falsifier**：反証対象とリポジトリ（読み取り専用）だけを渡し、書き手の弁明や検討の経緯を渡さない。Codex 環境では Codex 自身のサブエージェント（spawn）で立てる
- **反証 5 ベクトル**：production fact との不一致 / invariant を破る反例 / failure 後の downstream state / safety direction / 負荷、容量、upgrade path
- **blocking は自己承認で閉じられない**：設計修正、保証の縮退、stage-out、人間判断の 4 ルートのみで閉じ、解消確認は falsifier が行う
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
