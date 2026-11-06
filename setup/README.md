# ニコメア

ニコニコ動画の広告主やギフト贈呈者へのお礼を映像に重ねる AviUtl2 用フィルタプラグインです。

## インストールと使い方

手動でインストールする場合は、ZIP 内の `SYNC_Nicomea` フォルダを AviUtl2 の `Plugin` フォルダ（通常は `C:\ProgramData\aviutl2\Plugin`）に配置します。

1. AviUtl2 のオブジェクトに「SYNC」グループの「ニコメア」フィルタを追加します。
2. 「動画ID」にニコニコ動画の ID または視聴 URL を入力し、「データ取得」を押します。
3. 「設定」で表示対象や書式を選びます。表示スタイルは横スクロール、縦スクロール、ページ切り替えから選べます。

## 配布 ZIP の作成とカタログ登録

1. Win64 の Release をビルドします。バッチは `Win64\Release\SYNC_Nicomea.auf2` を使用します。
2. [xxHash の Windows 版](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)の `xxhsum.exe` を `Win64\Dependencies\xxHash-0.8.4` か PATH の通ったフォルダに置きます。
3. `SYNC_Nicomea.catalog.json` の `version` 配列の末尾に公開タグと公開日を設定します。次の版を出すときは配列の末尾に追加します。
4. `setup\make_release_zip.bat` を実行します。`setup\SYNC_Nicomea.zip` を作り、収録した `.auf2` の `XXH3_128` を末尾のバージョンに記録します。別の出力先や `xxhsum.exe` を使う場合は `-ReleaseDirectory`、`-XxhsumPath` で指定できます。
5. カタログの説明欄が参照するリポジトリ直下の `README.md` とロゴ画像 `Thumnail/thumnail.gif` を GitHub の `main` に push します。指定のタグで GitHub Release を作って ZIP を添付し、AviUtl2 カタログ v0.3.3 の「パッケージ登録」で `SYNC_Nicomea.catalog.json` を読み込んでインストールテストを実行します。
