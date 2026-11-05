# SYNC_Nicomea 作業ノート

## プロジェクトの前提

- Delphi プロジェクト名は `SYNC_Nicomea`。AviUtl2 のグループ名は `SYNC`、プラグイン名は「ニコメア」。
- `D:\DelphiProg\MyApp\SYNC_LipSync` からプロジェクトとソースをコピーした。ビルド後イベントは移植元の処理を引き継ぎ、出力名と配置先を新しいプロジェクト名に合わせる。

## 目的と設定画面

- ニコニコ動画の動画 ID を指定して広告・ギフト情報を取得し、AviUtl2 の映像に重ねて表示するためのフィルタープラグイン。取得処理と履歴の画面表示は `D:\DelphiProg\test\Comment\git` の `IdFrame`、`Thanks`、`Gift` を参照する。
- 設定画面は左に AviUtl2 の背景プレビュー、右上に動画 ID、右下に「広告」「ギフト」の切り替えとそれぞれの履歴欄を配置する。動画 ID はオブジェクトごとの「JSONデータ」の `videoId` に保存する。
- 動画 ID、視聴 URL、短縮 URL を入力し、「取得」または Enter で広告、ギフトの順に履歴を取得する。どちらも次ページがある間は取得を続け、経過と成否を取得ログに表示する。
- 取得履歴は設定画面の一覧で確認できる。映像への描画は今後の実装範囲とする。

## ビルド

- Delphi 37.0、Win64。IDE では `SYNC_Nicomea.dproj` を直接開き、Debug / Release をそれぞれビルドする。警告・エラーともに 0 を原則とする。
- プロジェクトのルートで次を実行する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_Nicomea.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_Nicomea.dproj /t:Build /p:Config=Release /p:Platform=Win64'
```

## ビルド後イベントとプロジェクト登録

- AviUtl2 プラグインの配置処理は、Delphi IDE のプロジェクトオプションにある「ビルド後イベント」に直接記述する。Debug / Release の両方で、`copy /Y` により DLL からローカルの `.auf2` を作成し、配置先へコピーする。両方のコピーが成功した後に `del /Q` で中間 DLL を削除する。Release では RSM も削除する。
- SYNC_Nicomea の配置先は `C:\ProgramData\aviutl2\Plugin\SYNC_Nicomea`。ローカルの成果物は `Win64\Debug\SYNC_Nicomea.auf2` と `Win64\Release\SYNC_Nicomea.auf2`。Debug と Release は同じ配置先にコピーされる。
- ユニットを追加したら、`.dpr` の `in` 指定と `.dproj` の `DCCReference` を両方更新する。フォームやフレームの IDE メタデータも対応させる。

## ソース配置

- `Source/Common` には、描画やデータ処理などの共通処理を機能別に置く。
- `Source/Plugin/Filter` には、AviUtl2 のコールバックや設定画面など、プラグイン固有の処理を置く。
- `Source/Lib` には、AviUtl2 SDK の型定義やフィルターテーブルの登録処理など、共通基盤を置く。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書く。公開処理には入出力と重要な副作用を記載し、状態の有効範囲、所有権、保存対象を必要に応じて明記する。コードをそのまま言い換えるコメントは避ける。
- 日本語を含む `.pas`、`.dpr`、Windows PowerShell 用の `.ps1` は UTF-8 BOM 付きとし、改行は CRLF とする。
- 1 ユニットは約 1,500 行を目安に責務で分け、関連ユニットは機能別フォルダーに置く。フォームの `.pas` と `.dfm` は同じフォルダーに置く。
- フォームは操作と画面状態を担当する。機能追加時は JSON の検証・解析、同期計算、描画をそれぞれの処理側に置く。JSON には設定値と素材の参照を保存し、MIDI や PSD の実データは埋め込まない。
- AviUtl2 SDK 型の順序・サイズ・配置を変える場合は、公式 SDK の定義と照合する。
