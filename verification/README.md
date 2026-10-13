# 検証の記録

確認日: 2026-10-12。この Mac の `/Applications/MATLAB_R2022b.app` を直接起動して確認しました。PATH に `matlab` がないことを理由に「MATLAB がない」と記載していた前回の判断を訂正します。`computer('arch')` は `maci64`、MATLAB Compiler のインストール・ライセンスはともに確認結果 0 でした。

| 確認 | 結果 | 確認できる範囲 |
| --- | --- | --- |
| MATLAB ソースの静的構文検査 | 9 ファイル、指摘なし | MISS_HIT 0.9.44、UTF-8、MATLAB 2022a 構文設定。API の存在・描画・実行結果は検証しない |
| JavaScript 計算部の数値検証 | 29 件すべて成功 | 平坦化・スピンの 16 件に、Mac 用の浸透モデル 13 件を追加 |
| MATLAB ネイティブの数値テスト | R2022b で 31 件すべて成功 | 解析解・保存則・収束・境界条件・停止時刻・不正入力 |
| MATLAB と Mac 計算部の比較 | 6 条件すべて許容差内で一致 | 膜厚・浸透長の最大差 1.110e-15 µm、許容差 1e-6 µm。平坦化、段差、任意行列、塗布・蒸発、充填の途中・完了 |
| Mac スタンドアローンのビルド | arm64 `.app` と ZIP を生成、ローカル署名の検証成功 | `dist/macos/20261012-194358/`。この端末用、Developer ID 署名・公証なし |
| Mac アプリ内での計算 | 3 モデルすべて完了、実行時エラーなし | 実際の WKWebView で各 61 時刻を生成し、指定した終了時刻まで到達 |
| Mac 画面・保存・読込 | 起動、平坦化実行、2D・立体表示、JSON 保存・復元、CSV・PNG 保存を確認 | CSV はヘッダーと 61 時刻、PNG は 1600 × 1110 px。保存内容を確認 |
| MATLAB UI の起動・描画・操作 | 未実行 | 実際の表示・操作は MATLAB 上で確認が必要 |
| Windows EXE とインストーラー | ビルド手順を用意、未生成 | Windows 上の MATLAB Compiler が必要 |
| MATLAB Runtime 上での動作 | 未実行 | 対象 Windows PC での確認が必要 |

MATLAB アプリは `+resist` 内のコードで計算します。Mac テスト版は JavaScript 参照実装と `macos/web/infiltration.js` を使用します。どちらも数値モデルの検証と画面の操作確認は区別して記録します。

Mac の確認結果は `output/mac-test/native-smoke-final.json`、MATLAB の比較データは `output/mac-test/matlab-parity.json`、実際の保存ファイルは同フォルダの `native-ui-*` に保存しています。計算部どうしの一致は実材料に対する予測精度の保証ではありません。Mac の全入力の組合せ、CSV 読込の全操作、一時停止・比較の網羅的な操作確認は未実施です。

比較データを再作成する場合は MATLAB で `addpath('matlab','verification'); exportParityFixtures('output/mac-test/matlab-parity.json');` を実行し、次に `node verification/js/compare-matlab.js output/mac-test/matlab-parity.json` で比較します。

```sh
# この開発環境で実行済み
npm test
mh_lint --ignore-config --input-encoding utf-8 --matlab 2022a matlab
```

MATLAB R2023b 以降で、プロジェクトのフォルダから次を実行してください。

```matlab
addpath('matlab');
results = runtests('matlab/tests');
assert(~isempty(results) && all([results.Passed]));
ResistFlowApp
```

画面では、各モードの実行、平坦化の一時停止と再開、時刻スライダー、条件の JSON 保存・再読込、膜厚・基板 CSV、比較、PNG 保存を確認します。CSV の中央断面と図の座標方向が一致すること、入力ミスやモデル限界で理由を表示することも確認してください。

Windows 上では `buildStandalone` がネイティブの数値テストを再実行し、合格時に配布物を作ります。作成したインストーラーを対象 PC に入れ、MATLAB 本体を起動せずに上記の操作を再確認してください。ビルド成功と配布先の動作確認は別の確認です。
