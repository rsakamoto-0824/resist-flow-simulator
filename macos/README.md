# Mac テスト版

この端末で 3 つのモデルを試すための、macOS 用スタンドアローンアプリです。生成された `Resist Flow Lab.app` をダブルクリックすると起動します。MATLAB、Node.js、別のブラウザー、インターネット接続は実行時に必要ありません。

このアプリは Swift / AppKit / WebKit と JavaScript の数値計算部から作られており、MATLAB Compiler で生成したアプリではありません。画面にも「Mac テスト版」と表示します。Windows 向け MATLAB アプリのコードは `matlab/` にあります。

2026-10-12 にこの端末向けの Apple Silicon 版をビルドし、起動・3 モデルの計算・条件 JSON の保存と復元・CSV と PNG の保存を確認しました。[ビルド済みアプリ](../dist/macos/20261012-194358/Resist%20Flow%20Lab.app)と[保管用 ZIP](../dist/macos/20261012-194358/ResistFlowLab-Mac-Test.zip)があります。まず「正弦波の平坦化」のまま「計算を実行」を押すと、凹凸が時間とともに平らになる様子を確認できます。

## 使い方

1. モデルまたはサンプル条件を選び、実行します。
2. 膜厚マップ、断面、時間変化を確認します。平坦化では一時停止と再開もできます。
3. 時間スライダーで計算途中の状態を表示できます。
4. 結果を保持して条件を変えると、1 件の結果と比較できます。
5. 条件は JSON、計算結果は CSV、図は PNG で保存できます。保存先は macOS の保存画面で選びます。

モデルの適用範囲、単位、校正が必要な材料値については画面の説明とプロジェクトの `design.md` を参照してください。入力と計算結果を外部へ送信する機能はありません。

## 再ビルド

ビルドには macOS、Xcode Command Line Tools、Node.js が必要です。実行する人にはこれらの開発ツールは不要です。

```sh
bash macos/build.sh
```

ビルドは数値テストを実行してから、この端末の CPU 向けにコンパイルします。生成先は `dist/macos/<日時>/` で、`.app` と ZIP が入ります。以前のビルドは上書きしません。最新のアプリの絶対パスは `output/mac-test/latest-app-path.txt` に記録されます。

この端末で使うためのローカル署名です。Apple の公証や一般配布向けの Developer ID 署名は行っていません。

## 確認用モード

ネイティブアプリ内部の WebKit で 3 モデルを実行し、JSON に検証結果を保存するモードがあります。

```sh
"<アプリのパス>/Contents/MacOS/ResistFlowLabMacTest" --self-test "<保存先>/native-smoke.json"
```

通常のダブルクリック起動では確認用モードを使いません。確認結果はプロジェクトの `verification/README.md` に記録します。
