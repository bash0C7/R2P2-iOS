# estalloc 破損の書き込み元特定・ワークアラウンド・bug report 実装 Plan

> **For agentic workers:** 各 task の実行フェーズは Sonnet subagent（Agent tool,
> `model: "sonnet"`）に委譲する。制御・ゲート判定・証拠の採否は main loop が行い、
> subagent には判定させず観測事実のみ返させる。Steps は checkbox（`- [ ]`）で追跡。

**Goal:** iOS Simulator crash の破損書き込み元を行レベルで特定し、R2P2-darwin 側のみの
ワークアラウンドを実 Simulator で検証し、環境非依存の決定論的再現付きで正しい upstream
リポジトリ宛の bug report を起草する。

**Architecture:** 安価な再現系（host libmruby.a + `bridge/picoruby_bridge.c` を clang
ビルドした `/tmp/innocence/harness` を `xcrun simctl spawn` 経由実行）で crash を再現し、
lldb attach で crash 時状態を観測して仮説（footer 上書き／est_free 誤読）を判別、その
結論に沿って書き込み元を watchpoint or read-only 整合性チェッカで特定する。ワークアラウンドは
`mrb_close` 除去（`free(heap)` が回収するため冗長）で、これは①に非依存で並行する。bug
report は estalloc standalone（`make test` の受け皿）での決定論的再現に落とす。

**Tech Stack:** clang / lldb / `xcrun simctl`（spawn・launch・install）/ xcodebuild
（rake 経由）/ picoruby estalloc（TLSF 系アロケータ、C）/ Ruby（rake harness）。

**参照 spec:** `docs/plans/2026-07-18-estalloc-writesite-workaround-report-design.md`

**前提リソース（HANDOFF より、着手前に存在確認）:**
- `/tmp/innocence/harness`（無ければ Task 0 で再ビルド）、`/tmp/innocence/main.c`
- host lib `build/host/lib/libmruby.a`（無ければ `RBENV_VERSION=4.0.5 rake macos:build`）
- Simulator `bisect-1` UDID `B82234B5-50A7-40FD-81EE-47CC9BEA7C2C`（booted 済み）
- crash 再現に必要な 4 環境変数の当時値は `/tmp/innocence/app_env.txt` に残存。UUID が
  変わり crash しない場合は Task 0 で再採取する。

---

## Task 0: 環境準備と crash baseline の再確認

**Files:**
- Rebuild (必要時): `/tmp/innocence/harness`（vendor 非改変・R2P2-darwin 非改変）
- Read: `HANDOFF.md` §2.2, `/tmp/innocence/app_env.txt`

- [ ] **Step 1: host lib と harness の存在確認**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/R2P2-darwin
ls -la build/host/lib/libmruby.a /tmp/innocence/harness /tmp/innocence/main.c
```
Expected: 3 ファイルとも存在。いずれか欠けていれば Step 2 で再生成。

- [ ] **Step 2: 欠損時のみ再ビルド**

host lib が無い場合:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/R2P2-darwin
export RBENV_VERSION=4.0.5
rake macos:build
```
harness が無い場合は HANDOFF §2.2 の clang コマンドをそのまま実行（`build/host/lib/libmruby.a`
にリンク）。Expected: `/tmp/innocence/harness` が生成される。

- [ ] **Step 3: crash baseline の再確認（simctl spawn 経由）**

Run:
```bash
UDID=B82234B5-50A7-40FD-81EE-47CC9BEA7C2C
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1 || xcrun simctl boot $UDID
export SIMCTL_CHILD_SIMULATOR_VERSION_INFO="$(grep '^SIMULATOR_VERSION_INFO=' /tmp/innocence/app_env.txt | cut -d= -f2-)"
export SIMCTL_CHILD_CFFIXED_USER_HOME="$(grep '^CFFIXED_USER_HOME=' /tmp/innocence/app_env.txt | cut -d= -f2-)"
export SIMCTL_CHILD_HOME="$SIMCTL_CHILD_CFFIXED_USER_HOME"
export SIMCTL_CHILD_TMPDIR="$SIMCTL_CHILD_CFFIXED_USER_HOME/tmp"
xcrun simctl spawn $UDID /tmp/innocence/harness 1; echo "exit=$?"
```
Expected: `exit=139`（SIGSEGV）。**この Task の完了ゲート**: crash がログ（`[harness] eval 0 begin`
の後に `HARNESS_DONE` が出ない）と exit code の両方で確認できること。crash しない場合は
`app_env.txt` の UUID が古い。実 app を一度 `simctl install`+`launch --wait-for-debugger` して
`launchctl procinfo` で 4 変数を再採取（HANDOFF §2.1/§2.2）してから再実行。

---

## Task 1: crash 時状態の観測と仮説判別（① keystone・read-only）

**Files:**
- Read: `vendor/picoruby/mrbgems/picoruby-mruby/lib/estalloc/estalloc.c`
  （`FREE_BLOCK`/`USED_BLOCK` 構造体、`BPOOL_TOP` マクロ、`IS_PREV_FREE`/`SET_PREV_FREE`、
  `add_free_block` ~315、`est_free` ~726、prev 合体 ~795-805）
- Read: `/tmp/innocence/lldb_crash_bt3.txt`
- Output: `/tmp/innocence/f1_run{1,2,3}.txt`

- [ ] **Step 1: estalloc の struct レイアウトを lldb 式に翻訳する準備**

`estalloc.c` を読み、次を確定して記録する: `FREE_BLOCK` の各フィールド offset
（`size`/`next_free`/`prev_free`/`top_adrs`）、`BPOOL_TOP(pool)` が指す先頭アドレスの計算式、
`IS_PREV_FREE(target)` が見る `size` のビット位置、`est_free` 内で `pool` にアクセスできる
経路（引数 or file-scope static `est`）。Expected: 各値を lldb の `p`/`memory read` 式に
落とせる状態。

- [ ] **Step 2: crash 停止時の状態を lldb で採取（run 1）**

Task 0 の 4 環境変数を export した状態で:
```bash
UDID=B82234B5-50A7-40FD-81EE-47CC9BEA7C2C
xcrun simctl spawn --wait-for-debugger $UDID /tmp/innocence/harness 1 &
sleep 1
PID=$(pgrep -x harness | tail -1)
lldb --batch \
  -o "attach --pid $PID" \
  -o "continue" \
  -k "bt" \
  -k "frame select 1" \
  -k "frame variable" \
  -k "register read" \
  -k "memory read --size 8 --format x \$x1-16 \$x1+32" \
  -o "quit" 2>&1 | tee /tmp/innocence/f1_run1.txt
```
続けて lldb セッション内（または追加の `-k`）で Step 1 で確定した式を使い次を読む:
`target` の値、`target->size` と PREV_FREE ビット、`target-8`（= 読まれた back-pointer、
`0x12` のはず）、`BPOOL_TOP(pool)` の値、`target - BPOOL_TOP(pool)`（相対オフセット）、
`BPOOL_TOP` から `size` チェーンを前方に辿った整合性（`target` に到達するか・size==0 や
境界外に飛ばないか・`target` の物理直前ブロックが free か used か）。Expected: これらの
生値が `f1_run1.txt` に記録される。

- [ ] **Step 3: 決定性確認（run 2, run 3）**

Step 2 を独立に 2 回繰り返し `f1_run2.txt`/`f1_run3.txt` に保存。Expected: crash ブロックの
BPOOL_TOP 相対オフセット・`0x12`・整合性の壊れ方が 3 回で一致するか否かを判定できる。

- [ ] **Step 4: 仮説判別（main loop がゲート）**

3 run の生データから結論を出す:
- **仮説A（footer 上書き）**: 物理直前ブロックが真に free・チェーン一貫・footer だけ `0x12`
  → Task 3A へ。書き込み元は footer への write。
- **仮説B（est_free 誤読）**: チェーン不整合、または物理直前ブロックが used なのに
  PREV_FREE フラグが立つ → Task 3B へ。欠陥は est_free/フラグ管理。
Expected: A/B いずれか（または第三の観測）が根拠つきで確定。決定性の有無も記録。
**この Task の完了ゲート**: 仮説が生データで裏付けられ、Task 3 の分岐と③の宛先方向
（estalloc 内部 or 外部 OOB）が定まること。

---

## Task 2: mrb_close 除去ワークアラウンドと実 Simulator 検証（②・①に非依存）

**Files:**
- Modify: `bridge/picoruby_bridge.c:110`（`repl_eval` の成功経路 `mrb_close`）
- Modify: `bridge/picoruby_bridge.c:207`（`vm_close` の `mrb_close`）
- Test（app）: `examples/ios/repl` を実 Simulator 起動
- Test（multi-eval/GC）: `/tmp/innocence/harness`（同じ改変 bridge を含む）を simctl spawn

- [ ] **Step 1: ワークアラウンドを適用**

`bridge/picoruby_bridge.c:110` の `mrb_close(mrb);` を、冗長性の根拠を残して無効化する:
```c
    mrc_ccontext_free(cc);
    /* Workaround: skip mrb_close; the estalloc pool is reclaimed wholesale by
     * free(heap) below, and mrb_close's teardown crashes in est_free (vendor
     * estalloc defect). Mirrors vendor's own picoruby cleanup(). */
    /* mrb_close(mrb); */
    global_mrb = NULL;
```
`bridge/picoruby_bridge.c:207` の `mrb_close(h->mrb);` も同様にコメントアウトし、直後の
`free(h->heap);` が回収する旨のコメントを添える。Expected: 成功経路の 2 箇所が無効化される。

- [ ] **Step 2: harness を再ビルドして multi-eval / GC 経路を先に検証（安価・高速）**

Task 0 の clang コマンドで harness を再ビルド（改変 bridge を含む）。Task 0 の 4 環境変数を
export した状態で:
```bash
UDID=B82234B5-50A7-40FD-81EE-47CC9BEA7C2C
# 1) 単発 puts
xcrun simctl spawn $UDID /tmp/innocence/harness 1; echo "exit=$?"
# 2) 2回目以降の eval（static est の再初期化確認）
xcrun simctl spawn $UDID /tmp/innocence/harness 3; echo "exit=$?"
# 3) GC 誘発（alloc 多め）
xcrun simctl spawn $UDID /tmp/innocence/harness 1 'n=0; 20000.times { |i| s=("x"*40); n+=s.length }; puts n'
echo "exit=$?"
```
Expected: 3 ケースとも `exit=0`、(1) は `hello 3`、(3) は `800000` を含む出力、いずれも
`HARNESS_DONE` がログに出る。crash（exit=139）が 1 つでも出たら workaround 不十分として
main loop に報告（次の hypothesis へ）。

- [ ] **Step 3: 実 Xcode app を実 Simulator で検証（primary）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/R2P2-darwin
export RBENV_VERSION=4.0.5
rm -rf build/ios-repl-sim build/ios-repl-app examples/ios/repl/Vendor
rake ios:lib ios:gen ios:build
UDID=B82234B5-50A7-40FD-81EE-47CC9BEA7C2C
APP=$(ls -d build/ios-repl-app/Build/Products/Debug-iphonesimulator/PicoRubyRunner.app)
xcrun simctl install $UDID "$APP"
xcrun simctl launch --console-pty $UDID com.bash0c7.picoruby.PicoRubyRunner
```
別 shell で `xcrun simctl spawn $UDID log stream` 相当、または launch 後に
`xcrun simctl get_app_container`/crash report ディレクトリ
（`~/Library/Logs/DiagnosticReports/`・Simulator 内 crash log）を確認。Expected: app が
non-crash で生存し、`hello 3` が console に出力され、新規 crash report が生成されない。

- [ ] **Step 4: Commit（ワークアラウンド）**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/R2P2-darwin
git add bridge/picoruby_bridge.c
git commit -q -m "fix(bridge): skip redundant mrb_close to avoid vendor estalloc teardown crash"
```
Expected: commit される。**この Task の完了ゲート**: Step 2・Step 3 の全確認が動作+ログで
成立。merge は提案しない（実機確認は user のみが宣言）。

---

## Task 3A: 書き込み元の watchpoint 追跡（仮説A のとき）

**Files:**
- Read: `estalloc.c`（`est_init` の pool 初期化、`add_free_block` の `top_adrs=self`）
- Output: `/tmp/innocence/f3a_watchpoint.txt`
- 診断挿入する場合のみ Modify（working tree のみ・commit 禁止・検証後 revert）:
  `estalloc.c`（read-only 整合性チェッカ）

- [ ] **Step 1: watchpoint 対象アドレスを相対オフセットで確定**

Task 1 の相対オフセット（`target - BPOOL_TOP`）が 3 run で決定的だったことを前提に、
`est_init` 直後に停止して `BPOOL_TOP(pool) + offset` を絶対アドレス化する lldb 手順を作る。
Expected: crash する footer 番地を実行早期に算出できる。

- [ ] **Step 2: est_init 直後に write watchpoint を張り run 全体を記録**

```bash
UDID=B82234B5-50A7-40FD-81EE-47CC9BEA7C2C
xcrun simctl spawn --wait-for-debugger $UDID /tmp/innocence/harness 1 &
sleep 1; PID=$(pgrep -x harness | tail -1)
lldb --batch \
  -o "attach --pid $PID" \
  -o "breakpoint set --name est_init" \
  -o "continue" \
  -o "<Step1 で作った: watchpoint set expression -w write -- (BPOOL_TOP+offset)>" \
  -o "continue" \
  -k "bt" -k "register read" \
  -o "quit" 2>&1 | tee /tmp/innocence/f3a_watchpoint.txt
```
watchpoint が HW で張れたことを確認（software watchpoint に落ちると非現実的に遅い）。
複数ヒットするので、`0x12` を書いた最後の write を書き込み元とする。Expected: `0x12` を
footer に書いた命令の PC・関数・backtrace が採れる。

- [ ] **Step 3: lldb 単独で不十分なら read-only 整合性チェッカを一時挿入**

watchpoint が決定性不足等で書き込み元を掴めない場合のみ、`est_free`/`add_free_block`
冒頭から呼ぶ read-only な pool 整合性チェッカを `estalloc.c` に一時挿入（struct 非改変・
`-O0` 維持・`write(2)`+固定バッファのみ）。harness を再ビルドし「最初に整合性が壊れる free の
通し番号」と当該ブロックダンプを採る。検証後:
```bash
git -C vendor/picoruby/mrbgems/picoruby-mruby/lib/estalloc checkout -- estalloc.c
git -C vendor/picoruby/mrbgems/picoruby-mruby/lib/estalloc status --short
```
Expected: 破損が起きる最初の free が特定され、estalloc submodule が clean に戻る。

- [ ] **Step 4: root-cause を 1 文で言語化（main loop がゲート）**

「どの不変条件が、どの条件下で破れるか」を 1 文で述べる。Expected: ③の issue root-cause 節と
宛先（estalloc 内部 or 外部 OOB）が確定。

---

## Task 3B: フラグ破損経路の追跡（仮説B のとき）

**Files:**
- Read: `estalloc.c`（`SET_PREV_FREE`/`CLR_PREV_FREE` 相当、`size` フラグを操作する全箇所、
  `merge_block`・`add_free_block`・`remove_free_block`）
- Output: `/tmp/innocence/f3b_flag.txt`

- [ ] **Step 1: crash した target の size フラグを書いた箇所を絞る**

Task 1 で「物理直前ブロックが used なのに PREV_FREE フラグが立つ」と判明した前提で、
`estalloc.c` 内で `target->size` の PREV_FREE ビットを立てる/落とすコード（`SET_PREV_FREE`
系マクロの全呼び出し）を列挙し、どの経路が本来 used のブロックに対しフラグを立てうるかを
コードで辿る。Expected: 候補箇所のリスト。

- [ ] **Step 2: target->size 番地に write watchpoint（相対オフセット化）**

Task 3A Step 1/2 と同じ手法で、footer ではなく `target->size` 番地（= `target` 相対
offset 0）に write watchpoint を張り、PREV_FREE ビットを誤って立てた write を捕捉する。
Expected: フラグを壊した命令の PC・関数・backtrace。

- [ ] **Step 3: root-cause を 1 文で言語化（main loop がゲート）**

Expected: 破れる不変条件と宛先（この経路は estalloc 内部濃厚）が確定。

---

## Task 4: estalloc standalone での決定論的再現（③・環境非依存）

**Files:**
- Read: `vendor/picoruby/mrbgems/picoruby-mruby/lib/estalloc/{test/test.c,Makefile,README}`
- Create: `/tmp/innocence/estalloc_repro/`（縮約再現一式、estalloc ソースをコピーして
  standalone ビルド。vendor tree は非改変）

- [ ] **Step 1: estalloc の standalone ビルド/テスト経路を把握**

`make test` の受け皿（`test/test.c` + `Makefile`）を読み、`est_init`/`est_malloc`/`est_free`
を単体で叩くテストの書き方・ビルド方法を確定。Expected: 環境変数・simctl・iOS に依存しない
ビルド手段が判明。

- [ ] **Step 2: Task 3 の結論に沿った縮約再現を書く**

Task 3 で確定した「破れる不変条件」を、`est_malloc`/`est_free` の最小シーケンス、または
当該不変条件を人工的に破る最小ケースとして `/tmp/innocence/estalloc_repro/` に書く。
estalloc ソースはコピーして使い vendor tree は触らない。Expected: `make`/`clang` でビルドでき、
実行すると SIGSEGV（または assert 発火）で決定論的に再現するテスト。

- [ ] **Step 3: 決定論の確認**

再現テストを 5 回連続実行し毎回同じ結果になることを確認。Expected: simctl/env なしで
100% 再現。**この Task の完了ゲート**: upstream メンテナが手元の `make` だけで再現できる
最小テストが存在。

---

## Task 5: 宛先確定と issue 草稿（③・投稿は user 承認必須）

**Files:**
- Read: estalloc submodule の git log（`971b793` 以降の修正確認）
- Create: `/tmp/innocence/issue_draft.md`

- [ ] **Step 1: estalloc upstream の状態確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/R2P2-darwin/vendor/picoruby/mrbgems/picoruby-mruby/lib/estalloc
git log --oneline -20
git remote -v
```
`971b793` 以降に同一欠陥の修正 commit が無いか、estalloc の upstream（`picoruby/estalloc`）を
確認。Expected: 既知修正の有無と宛先リポジトリ（estalloc 内部欠陥 → `picoruby/estalloc`、
外部 OOB → mruby/picoruby）が確定。

- [ ] **Step 2: issue 草稿を書く**

`/tmp/innocence/issue_draft.md` に: 症状 / crash backtrace（`lldb_crash_bt3.txt`）/ Task 3 の
root-cause（破れる不変条件）/ Task 4 の決定論的再現手順 / 修正案。修正案は Phase D の
境界チェックガードを載せるが「正当な合体ケースを誤って skip しない保証は未検証（症状抑制で
あり根本修正ではない）」と明記。`simctl spawn`/長い環境変数は trigger の一例として補足に留め、
主張は不変条件に置く。Expected: メンテナが再現・triage できる草稿。

- [ ] **Step 3: user へ提示（投稿はしない）**

草稿を user に提示し、投稿可否・宛先・文面の承認を得る。Expected: **issue 投稿は user 承認まで
行わない**（外向きの不可逆操作）。

---

## Self-Review（spec との突き合わせ）

- **spec ① 書き込み元特定** → Task 1（観測・判別）+ Task 3A/3B（追跡）。✓
- **spec ② ワークアラウンド** → Task 2（`mrb_close` 除去 + Simulator 検証、multi-eval/GC 含む）。✓
- **spec ③ bug report** → Task 4（決定論的再現）+ Task 5（宛先確定・草稿・user 承認）。✓
- **依存関係（①→③、②独立）** → Task 順で担保（②と①観測を先行、①追跡→③）。✓
- **制約（vendor 非 commit・ESTALLOC_DEBUG 不使用・投稿は user 承認）** → Task 3A Step3・
  Task 5 Step3 に明記。✓
- **完了基準（実 Simulator・動作+ログ）** → Task 0/2 のゲートに明記。✓
- Placeholder scan: 探索的 step（lldb 読み取り）は「手順 + 完了ゲート」で記述、固定コマンド部は
  正確な path/UDID/環境変数を明記。TBD なし。✓
