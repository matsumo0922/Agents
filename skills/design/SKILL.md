---
name: design
description: "GitHub issue や作業説明を起点に、最上位ティアの architect サブエージェントがコードを読んで候補アプローチを比較し、独立反証と人間判断が必要な論点の構造化質問を経て、実装エージェントにそのまま渡せる設計契約準拠の設計ドキュメントをローカルに作る。ユーザーの指示があれば issue の「## 設計」セクションとして投稿する。Use when the user asks to design a feature or fix before implementation, create a design document, 設計して, 設計を作って, 実装方針を固めて, アーキテクチャを決めて, ## 設計を書いて, or to prepare an issue for issue-pr-autopilot."
---

# Design

GitHub issue または会話中の作業説明を対象に、実装前の設計を確定する。要件の言い換えではなく構造の決定を行う: 新規コンポーネントの居場所と責務、ファイル単位の変更マップ、状態遷移・境界（lock / transaction / API contract）の決定。成果物はローカルの設計ドキュメント `/tmp/design/<slug>.design.md` であり、実装・コード変更は行わない。

Codex / Claude Code など複数の実行環境から使われるため、特定製品の機能名に依存しない。「構造化質問ツール」は Claude Code では AskUserQuestion、Codex では request_user_input を指し、どちらも無い環境では番号付き選択肢のテキスト質問で代替する。環境固有の最適化は末尾の「環境別ヒント」に従う。

本スキルは dig / design / issue-pr-autopilot からなるパイプライン bundle の一部として配布される（`make link` で一括リンク。単体配布はサポートしない）。設計の形式は設計契約が正本であり、issue-pr-autopilot の設計ゲート・レビューも同じ契約を参照する。

## 全体方針

- main agent は薄いオーケストレーターに徹する。コード読解と設計立案は architect サブエージェントに委任し、main agent は対象特定・反証の発動判定・質問の提示・決定の記録・issue への投稿を行う。対象コードと分析過程（台帳）を main agent のコンテキストに読み込まない。確定した設計ドキュメントは読んでよく、ユーザーとの議論と最終確認にはむしろ読んで臨む。
- サブエージェントを spawn・継続するたびに、割り当てたモデル名と effort をユーザーへの報告に明示する。
- このスキルをサブエージェントや fork されたコンテキストで実行しない（構造化質問がユーザーに届かない）。
- 単一レイヤーで自明な変更には使わない。設計不要なものは issue-pr-autopilot の設計ゲートがそのまま通す。
- dig は前提への挑戦、本スキルは構造の決定を担う。要件が未確定なまま設計に入らない（Phase 1 参照）。

## ファイル

slug は対象を表す短い英語スラッグとし、次のファイルを使い分ける。

- 台帳 `/tmp/design/<slug>.md`: 要件、分析過程、質問ログ。main agent とサブエージェントの間では要約だけをやり取りする。
- 設計ドラフト `/tmp/design/<slug>.draft.md`: architect が書く設計本文のみのドラフト。反証パスの入力になる（分析過程を含めないことで falsifier の anchor を防ぐ）。
- 設計ドキュメント `/tmp/design/<slug>.design.md`: 確定した設計だけを置く成果物。実装エージェントに渡すのはこのパスだけとする。

設計契約の reference（この SKILL.md があるディレクトリからの相対パス。サブエージェントは SKILL.md の所在を知らないため、main agent が絶対パスへ解決して指示に埋め込む）:

- `references/design-contract.md`: core design schema（必須 8 セクション、条件付き matrix 4 種と発動条件、非該当宣言、帰属、高リスク未検証前提プロトコル）。architect が読む。
- `references/falsifier-rubric.md`: 反証 5 ベクトル、falsifier の職掌、返却形式。falsifier と自己反証時の architect が読む。
- `references/design-examples.md`: 各セクションの記入例。必要時のみ参照する。

## Phase 1: 対象特定

- 引数 → 会話文脈 → 直近に話題になった issue の順で対象を特定する。issue の場合は `gh issue view <number> --comments` を **1 回だけ**実行する。
- 要件（作業内容・受け入れ条件・スコープ外）を台帳に書き出す。会話中に既に設計議論があれば、その結論を決定事項として登録し、architect の入力にする。dig を実施済みの場合は、その記録ファイルの Decisions を要件・事実・仮定として台帳へ転記する。
- 対象 issue に既に「## 設計」がある場合は更新モードとする。既存設計を台帳に転記し、architect には差分の設計だけを依頼する。
- 要件が曖昧（受け入れ条件が無い、前提が未検証、スコープが揺れている）と判断した場合は、Phase 2 に入る前に dig を実行して要件を確定させ、その決定を台帳に転記する。起動方法は環境別ヒントに従う。

## Phase 2: architect サブエージェント

```text
<architect_instruction>
あなたは設計 architect サブエージェントです。コードを変更せず、実装前の設計だけを行ってください。

<scope>
- 台帳: /tmp/design/<slug>.md（要件と既知の決定が書いてある。必読）
- 設計契約: <references/design-contract.md の絶対パス>（設計の形式と記入基準。必読。記入例が必要なら同ディレクトリの design-examples.md を参照）
- 対象リポジトリ: <absolute path>（読み取りのみ）
</scope>

<rules>
禁止: コード・ドキュメントの変更 / 自分のサブエージェントの spawn / issue 本文の再取得。

- 関連コードを読み、候補アプローチを 2〜3 案、trade-off 付きで比較して 1 案を推す。比較過程は台帳に書く。
- 推し案を設計契約の形式で具体化し、設計本文だけを /tmp/design/<slug>.draft.md に書く（台帳の分析過程を混ぜない）。
- 契約の必須セクションをすべて書く。特に「事実と仮定」は config / DB 保存値 / runtime 値 / 表示値の正本を分離し、確認方法の無い値を事実表に書かない。「スコープ判定」は客観 signal（layer 数・不可逆 migration・security boundary・consumer 数・DB hot path）を根拠に書く。条件付きセクションは発動条件を判定し、非該当は契約の宣言ルールに従う。
- 品質基準: 初見の実装者が設計とリポジトリだけで完遂できる自己完結性を保つ / 変更予定ファイルは「ファイル → 何をするか」の粒度で書く / 新規コンポーネントは置き場所（module / package）と責務を決める / 決定は「〜とする」の形で書き、読み手に委ねない / 受け入れの確認方法は観測可能な形（コマンド・URL・表示）で書く。
- 構造の判断（どの層に置くか、どう分割するか）は自分で決める。ユーザーの価値判断・リスク許容・運用方針に関わる論点だけを「要質問」とし、選択肢 2〜4 個と各選択肢の trade-off 1 行を付けて返す。high リスクかつ未検証の仮定は契約の高リスク未検証前提プロトコルに従い、自分で検証を試みた上で残ったものを「要質問」に含める。
</rules>

<deliverables>
main agent には次だけを返してください。設計の全文は返さないでください。
1. 推奨アプローチの 1 行要約と、比較した代替案（各 1 行）
2. 変更予定ファイル map の要約と、設計が触れる範囲（layer 数 / safety / migration / security / consumer 数 / DB hot path の該当有無）
3. 条件付きセクションの発動判定結果（発動したもの・非該当宣言したもの）
4. 要質問の論点（質問文・選択肢・trade-off）。なければ「なし」
5. 高リスク・未検証のまま残っている仮定の一覧。なければ「なし」
6. ドラフト（/tmp/design/<slug>.draft.md）への書き込み完了の確認
</deliverables>
</architect_instruction>
```

## Phase 3: 質問ラウンド

- architect が返した「要質問」の論点だけを構造化質問ツールで提示する。1 ラウンド 2〜3 問、上限 2 ラウンド。
- high リスクかつ未検証の仮定は、対話中はこの質問ラウンドで確定させる（設計契約の高リスク未検証前提プロトコルの対話分岐）。
- どの選択肢が選ばれても設計が変わらない質問は提示しない。質問がコード内部の語彙に寄っていて伝わりにくい場合は、main agent が提示前に文言を調整してよい。ただし新しい論点の発明は architect に任せる。
- ラウンド中の自由形式の反論・確認には、architect の要約と要件の範囲で答えられるものだけ main agent が直接応答する。コード読解が必要なものは「確認する」と明示し、次の継続依頼に含める。
- 回答を台帳に追記し、同じ architect に反映を依頼する（再 spawn しない。継続できない環境では前回の要約と回答を添えて再依頼する）。反映後のドラフトが反証パスの入力になる。
- 2 ラウンドで収束しない論点、およびユーザーが「その他」で保留した論点は「agent 仮決め」として設計に残す（high リスク未検証は仮決めにできない。プロトコルに従う）。

## Phase 3.5: 反証パス

設計確定前に、ドラフトを反証する。実施形態は main agent が判定する。

- **発動判定（main agent）**: architect の deliverable 2 の範囲情報を、客観条件リスト — cross-layer 変更 / safety / migration / security / 複数 consumer / DB hot path — に照らして判定する。layer の定義は issue-pr-autopilot の gate schema と同一（module / process / API 境界 / DB schema / UI / 権限・deployment の構造境界。2 つ以上の layer の契約を同時に変えるなら cross-layer）。architect 自身に「該当なし」と判断させない。判定に迷う場合は発動する側に倒す。
- **いずれかに該当する場合**: clean context の falsifier サブエージェントを 1 体 spawn する（必須。architect の条件付き matrix 発動判定に依存させない）。

```text
<falsifier_instruction>
あなたは設計の反証者です。コードを変更せず、渡された設計ドラフトの反証だけを行ってください。

- 設計ドラフト: /tmp/design/<slug>.draft.md
- rubric: <references/falsifier-rubric.md の絶対パス>（職掌・反証 5 ベクトル・返却形式。必読）
- 対象リポジトリ: <absolute path>（読み取りのみ）

rubric の職掌 4 点（反例列挙 / matrix 発動判定の妥当性 / スコープ判定の妥当性 / 見落とし前提)を検証し、falsification_result 形式で返してください。処置の決定はしないでください。
</falsifier_instruction>
```

- **いずれにも該当しない場合**: 同一 architect に、falsifier-rubric.md に従った自己反証を別ターンで依頼する。
- main agent は falsification_result を architect に渡し、architect が各反例の処置（設計修正 / 受容 + 理由）を決めてドラフトの「反証」セクションへ記録する。matrix 発動判定・スコープ判定の誤りが指摘された場合は該当セクションを修正する。反証で新たに要質問の論点（価値判断）が生じた場合は Phase 3 の残ラウンドで確定させる。

## Phase 4: 設計確定（G1）

次がすべて成立して初めて設計を確定できる。main agent がドラフトのセクション構造で確認する。

1. 契約の必須 8 セクションと、発動した条件付きセクションがすべて存在する。
2. 「反証」セクションに反証パスの結果と全反例の処置が記録されている。
3. high リスクかつ未検証の仮定が残っていない（質問で確定済み、または契約のプロトコルで処置済み）。
4. 「スコープ判定」が記載されている。網羅不能の場合は staged PR 分割案があり、対話中はユーザーに分割方針を質問して確定している。

成立したら architect にドラフトを `/tmp/design/<slug>.design.md` へ確定させ、main agent はこれを読み、要件・質問ラウンドの決定との整合を確認してからユーザーに報告する（以降のユーザーとの設計議論はこのドキュメントを根拠に main agent が直接応答し、コードレベルの再調査が必要なときだけ architect を継続する）。設計ドキュメントの中身は設計契約の「## 設計」形式そのものであり、issue へ投稿するときは本文へそのまま追記できる。

- 決定事項の帰属は契約の帰属ルールに従う（ユーザー確認済み / agent 仮決め / 高リスク・要人間確認）。仮決めとマーク付き前提は issue-pr-autopilot が「人間に確認してほしいこと」へ転記する対象になる。
- ユーザーが issue への投稿を指示した場合（issue-pr-autopilot に別セッション・別マシンで渡す等）だけ、設計ドキュメントを issue 本文の「## 設計」セクションとして追記・置換する（`gh issue view --json body` で現本文を取得し、編集後に `gh issue edit --body-file`）。`/tmp` は永続しないため、セッションを跨いで使う予定が見えるときは投稿を一言提案してよい。
- 完了時、チャットには要約だけを出す: 推奨アプローチ 1 行 / 決定 N 件（うち仮決め N 件・要人間確認 N 件）/ 反証の反例 N 件と処置 / 設計ドキュメントのパス（投稿した場合は issue URL）。設計全文の再掲はしない。

## 環境別ヒント

コア原則: architect と falsifier は 1〜2 パスで品質が決まる役割のため、最上位ティアの高 effort を割り当てる。コードの長文脈読解を伴うため最軽量ティアを使わない。spawn 時のモデル名と effort の申告を忘れない。

### Claude Code

- architect / falsifier = Fable 5（`effort: high`）。質問反映の継続は SendMessage で行い、再 spawn しない。falsifier は新規 spawn する（clean context のため継続にしない）。
- main agent は role 別 reference（design-contract.md 等）を読まず、絶対パスへ解決してサブエージェント指示に埋め込む。
- 構造化質問は AskUserQuestion。1 回の呼び出しで最大 4 問だが、本スキルでは 2〜3 問に抑える。
- plan mode 中に呼ばれた場合は、ExitPlanMode でプランを提示する前に設計を確定し、プランへ反映する。
- このスキルを Agent tool 経由のサブエージェントとして実行しない（AskUserQuestion がユーザーに届かない）。
- dig の起動は Skill tool で行う（main 会話内で実行されるため質問がユーザーに届く）。

### Codex

- main agent = `gpt-5.6-sol`（`model_reasoning_effort = "medium"`、`plan_mode_reasoning_effort = "high"`）を推奨する。
- architect / falsifier = `gpt-5.6-sol`（`model_reasoning_effort = "xhigh"`）。読み込み中心のため組み込みの explorer エージェントが向く。falsifier は `fork_turns = "none"` で clean context にする。
- Codex の skill runtime 規則（SKILL.md が必須参照する resource にサブエージェントが従う場合、main もその reference を読む）に従い、main はその run で必要になった reference（設計契約等）を読んでよい。読む対象を role 別 reference に絞り、不要な reference を読まない。
- 構造化質問は request_user_input（1〜3 問）。
- dig の起動は `$dig` 参照で行い、使えない場合は `~/.codex/skills/dig/SKILL.md` を読み込んで従う。
- `/goal` 自走中はこのスキルを使わない（対話質問ができない）。自走中に設計が無い場合は issue-pr-autopilot の設計ゲートが代替する。
