# ニコメア（SYNC_Nicomea）

ニコニコ動画の広告主やギフト贈呈者へのお礼を、動画のエンドロールなどに表示する AviUtl2 用フィルタプラグインです。動画 ID または視聴 URL から広告・ギフトの履歴を取得し、名前やポイントを指定した書式で表示できます。

![ニコメアのロゴ](https://raw.githubusercontent.com/vramwiz/SYNC_Nicomea/main/Thumnail/thumnail.gif)

## インストール

1. [GitHub Releases](https://github.com/vramwiz/SYNC_Nicomea/releases) から `SYNC_Nicomea.zip` をダウンロードして展開します。
2. 展開した `SYNC_Nicomea` フォルダを AviUtl2 の `Plugin` フォルダにコピーします。標準の配置先は `C:\ProgramData\aviutl2\Plugin\SYNC_Nicomea\SYNC_Nicomea.auf2` です。
3. AviUtl2 を起動します。起動中に配置した場合は再起動します。

## 使い方

1. オブジェクトに **SYNC → ニコメア** フィルタを追加します。
2. **動画ID** にニコニコ動画の ID（例 `sm12345678`）または視聴 URL を入力し、**データ取得** を押します。
3. **設定** を開き、表示対象を広告またはギフトから選びます。書式と表示スタイルを調整し、プレビューを確認して **OK** を押します。

表示スタイルは横スクロール、縦スクロール、ページ切り替えの3種類です。オブジェクトの長さに合わせてスクロールやページ切り替えが進みます。設定画面では文字色、縁取り、影、表示領域、フェードなどを調整できます。

書式欄を右クリックすると、選択中の表示対象で使える記号を挿入できます。たとえば `%nさん（%p pt）` と入力すると、名前とポイント合計を表示できます。

## ビルド・配布

Delphi で `SYNC_Nicomea.dproj` を開き、Win64 の Release 構成をビルドします。ZIP の作成とカタログ登録の手順は [配布手順](https://github.com/vramwiz/SYNC_Nicomea/blob/main/setup/README.md) を参照してください。

## ライセンス

[GNU General Public License v3.0](https://github.com/vramwiz/SYNC_Nicomea/blob/main/LICENSE)
