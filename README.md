# TripLog

旅ごとに1冊の「旅ノート」を作る、iPad用のアプリです（Swift Playgrounds で開発）。

- 写真を入れるだけで、行った県の地図と撮影地の道のりが自動で描かれます
- 写真は撮影日時の順に並び、タッチすると大きく見られます
- ペンで手書きのメモを残せます
- 旅ごとにノートが増えていき、本棚で「行った県 ○ / 47」が分かります

`TripLog.swiftpm` フォルダが Swift Playgrounds で開けるアプリ本体です。
アプリ内の版番号は `MyApp.swift` の `appVersion` で管理しています。

- 地図データ：地球地図日本（© 国土地理院、加工して使用）、湖：Natural Earth
- 手書き風フォント：Google Fonts（SIL Open Font License）
