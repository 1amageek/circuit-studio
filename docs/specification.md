# CircuitStudio 設計仕様書

## 設計思想: Live Circuit Design

CircuitStudio は「回路は常に生きている」をコンセプトとする回路エディタである。

従来のツールは「描画 → 保存 → シミュレーション実行 → 結果確認」というバッチ処理パイプラインを前提としている。CircuitStudio は CoreSpice をインプロセスで保持し、編集操作がリアルタイムにシミュレーション結果へ反映される**ライブフィードバックループ**を実現する。

### 我々だけが持つ技術的優位性

| 強み | 根拠 | 競合との差 |
|------|------|-----------|
| **インプロセス SPICE** | CoreSpice が同一プロセスで動作。テキストパース・プロセス間通信なし | KiCad/Qucs-S は ngspice を外部プロセスとして起動 |
| **IncrementalUpdate** | パラメータ変更時にマトリクス全体を再構築せず、変更デバイスのスタンプのみ更新 | 全競合ツールはフルリコンパイル |
| **リアルタイムイベントストリーム** | Newton 反復、タイムステップ、GPU ディスパッチ等の粒度でイベント発行 | LTspice はログ出力のみ、ngspice はコンソール出力のみ |
| **Metal GPU 演算** | 512 ポートフォトニックメッシュの GPU 並列演算 | 他ツールに GPU バックエンドなし |
| **ゼロコピー波形アクセス** | WaveformData を Swift 構造体として直接参照。型付きアクセサで単位変換 | ngspice は .raw ファイルパース、LTspice はバイナリパース |
| **Swift 厳格並行性** | async/await、CancellationToken、Sendable 型による安全な非同期実行 | C ベースエンジンはスレッド安全性が保証されない |
| **ネイティブ macOS** | SwiftUI Canvas、トラックパッドジェスチャー、システムカラー、アクセシビリティ | LTspice は Wine/CrossOver、KiCad は wxWidgets、Qucs-S は Qt |

---

## アーキテクチャ概要

### モジュール構成 (Package.swift)

```
CircuitStudioApp ──┬── SchematicEditor ──── CircuitStudioCore ──── CoreSpice
                   ├── WaveformViewer ───── CircuitStudioCore        ├── CoreSpiceIO
                   └── LayoutEditor ──┬── LayoutCore                 └── CoreSpiceWaveform
                                      ├── LayoutTech ──── LayoutCore
                                      ├── LayoutVerify ── LayoutCore + LayoutTech
                                      ├── LayoutIO ────── LayoutCore + LayoutTech
                                      └── LayoutIntegration ── LayoutCore + LayoutTech + LayoutIO + LayoutVerify
```

**ライブラリ (10 プロダクト)**:
CircuitStudioCore, SchematicEditor, WaveformViewer, CircuitStudioApp,
LayoutCore, LayoutTech, LayoutVerify, LayoutIO, LayoutIntegration, LayoutEditor

### シミュレーションパイプライン

```
┌─────────────────────────────────────────────────────────┐
│                   CircuitStudio                          │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Schematic   │  │   Layout     │  │  Waveform    │  │
│  │  Editor      │  │   Editor     │  │  Viewer      │  │
│  └──────┬───────┘  └──────────────┘  └──────▲───────┘  │
│         │                                    │          │
│  ┌──────▼────────────────────────────────────┤          │
│  │           Simulation Pipeline              │          │
│  │                                            │          │
│  │  SchematicDocument                         │          │
│  │       │                                    │          │
│  │  NetExtractor ──► ExtractedNets            │          │
│  │       │                                    │          │
│  │  NetlistGenerator ──► SPICE Source         │          │
│  │       │                                    │          │
│  │  SimulationService                         │          │
│  │       ├── CoreSpice (in-process)           │          │
│  │       │   Parse → Lower → Compile → Bind   │          │
│  │       │   Analysis.run() ──────────────────┤          │
│  │       │                                    │          │
│  │       └── ExternalSpiceSimulator (ngspice) │          │
│  │           ↕ ProcessConfiguration            │          │
│  │                                            │          │
│  │  AsyncStream<SimulationEvent>              │          │
│  │       └── WaveformData ────────────────────┘          │
│  └───────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘
```

### パイプライン特性

| 段階 | レイテンシ目標 | 手法 |
|------|-------------|------|
| 編集 → ネット抽出 | < 1ms | Union-Find (O(α(n))) |
| ネット → ネットリスト | < 1ms | 直接文字列生成 |
| ネットリスト → コンパイル | < 10ms | StandardCompiler + SparseStructure |
| パラメータ変更 → 再スタンプ | < 1ms | IncrementalUpdate (変更デバイスのみ) |
| DC OP 実行 | < 50ms | Newton-Raphson (小規模回路) |
| 結果 → 表示更新 | < 16ms | @Observable + SwiftUI diff |

---

## 1. ドキュメントモデル

### 1.1 SchematicDocument

回路図の完全な状態を表現する値型。

```
SchematicDocument
├── components: [PlacedComponent]   // 配置済みコンポーネント
├── wires: [Wire]                   // 配線
├── labels: [NetLabel]              // ネットラベル
├── junctions: [Junction]           // 自動算出ジャンクション
└── selection: Set<UUID>            // 選択状態
```

> **計画中**: `noConnects: [NoConnect]` (未接続フラグ)、`powerSymbols: [PowerSymbol]` (電源シンボル) は将来追加予定。現在は Ground/Terminal を通常のコンポーネントとして扱っている。

#### PlacedComponent

```swift
struct PlacedComponent: Sendable, Identifiable {
    let id: UUID
    var deviceKindID: String       // DeviceCatalog キー (例: "resistor", "nmos_l1")
    var name: String               // インスタンス名 (例: "R1", "M2")
    var position: CGPoint
    var rotation: Double           // 度数
    var mirrorX: Bool              // 水平軸反転
    var mirrorY: Bool              // 垂直軸反転
    var parameters: [String: Double]  // ParameterSchema.id をキーとするパラメータ値
    var modelPresetID: String?     // モデルプリセット ID (nil = カスタム)
    var modelName: String?         // 外部モデル名オーバーライド
}
```

#### Wire

```swift
struct PinReference: Sendable, Hashable, Codable {
    let componentID: UUID
    let portID: String             // PortDefinition.id (例: "pos", "neg", "drain")
}

struct Wire: Sendable, Identifiable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var startPin: PinReference?    // 始点接続ピン (nil = フリーエンド)
    var endPin: PinReference?      // 終点接続ピン (nil = フリーエンド)
    var netName: String?           // ネット名
}
```

ワイヤーは端点でピンへの明示的参照を保持する。これにより移動・回転・ミラー時にラバーバンド追従が可能となる。

#### NetLabel

```swift
struct NetLabel: Sendable, Identifiable {
    let id: UUID
    var name: String
    var position: CGPoint
}
```

### 1.2 Junction

```swift
struct Junction: Sendable, Identifiable {
    let id: UUID
    var position: CGPoint
}
```

ジャンクションは**自動算出方式**を採用する。ワイヤー端点が 3 本以上重なる位置に自動生成される。ワイヤー追加・削除・移動時に `recomputeJunctions()` で再計算する。既存ジャンクションの ID は安定性のために保持される。

ワイヤーが既存ワイヤーの中間に接続された場合、既存ワイヤーを分割して T 字接合を正しく検出する (`splitWiresAtEndpoints`)。

### 1.3 計画中の型

**NoConnect** — ピンの意図的未接続マーク。ERC でピン未接続警告を抑制するために使用する。

**PowerSymbol** — グローバル電源ネット (VCC, VDD, VSS 等)。現在は Ground/Terminal を通常のコンポーネント (BuiltInDevices) として実装している。

### 1.4 Undo/Redo

```swift
struct UndoStack: Sendable {
    private var undoEntries: [SchematicDocument]
    private var redoEntries: [SchematicDocument]
    private let maxDepth: Int      // デフォルト 100

    mutating func record(_ document: SchematicDocument)
    mutating func undo(current: SchematicDocument) -> SchematicDocument?
    mutating func redo(current: SchematicDocument) -> SchematicDocument?
    var canUndo: Bool
    var canRedo: Bool
}
```

ドキュメント全体のスナップショット方式を採用する。SchematicDocument は値型(struct)であるため、コピーコストは低い。Copy-on-Write により実際のメモリコピーは変更のあった配列のみに発生する。`undo()`/`redo()` は現在のドキュメントを引数で受け取り、反対スタックに退避する。

---

## 2. 編集操作

### 2.1 ツールモード

```swift
enum EditTool: Sendable {
    case select              // 選択・移動
    case place(String)       // デバイス配置 (DeviceCatalog ID)
    case wire                // ワイヤー描画 (2 クリック方式)
    case label               // ネットラベル配置
}
```

> **計画中**: `case junction` (手動ジャンクション配置)、`case noConnect` (NoConnect 配置)、`case power(PowerSymbolStyle)` (電源シンボル配置) は将来追加予定。現在ジャンクションは自動算出のみ。

### 2.1.1 ヒットテスト

```swift
enum HitResult: Sendable {
    case component(UUID)
    case wire(UUID)
    case label(UUID)
    case junction(UUID)
    case pin(componentID: UUID, portID: String)
    case none
}
```

ヒットテストは優先度順に判定する: ピン → コンポーネント → ワイヤー → ジャンクション → ラベル。ピンは `gridSize * 0.8` 以内、ワイヤーは線分距離 5pt 以内で判定する。

### 2.2 キーボードショートカット体系

LTspice の左手キーボード/右手マウス最適化と KiCad の単一キー直感性を融合する。

**設計原則**:
- 修飾キーなしの単一キーで最頻操作にアクセス
- `Esc` で常にデフォルト(Select)に戻る
- モード切替はキーを押すだけ(トグルではない)

#### ツール切替キー

| キー | 操作 | 根拠 |
|------|------|------|
| `Esc` | Select モードに戻る | 全ツール共通の慣行 |
| `W` | Wire モード | KiCad と同一。"Wire" の頭文字 |
| `P` | Place モード (パレット表示) | KiCad `A` より直感的。"Place" の頭文字 |
| `L` | Label 配置 | "Label" の頭文字 |
| `J` | Junction 配置 | KiCad/Altium と同一 |
| `Q` | NoConnect 配置 | KiCad `Q` に準拠 |
| `G` | Ground 配置 | LTspice と同一 |

#### 編集操作キー

| キー | 操作 | 根拠 |
|------|------|------|
| `R` | 回転 (90° CW) | 全ツール共通 |
| `X` | X 軸ミラー | KiCad/Altium と同一 |
| `Y` | Y 軸ミラー | KiCad/Altium と同一 |
| `M` | 移動 (接続切断) | KiCad と同一 |
| `D` | ドラッグ (接続維持) | KiCad `G` に相当。"Drag" の頭文字 |
| `Delete` / `Backspace` | 削除 | macOS 標準 |
| `Cmd+C` / `Cmd+V` / `Cmd+X` | コピー / ペースト / カット | macOS 標準 |
| `Cmd+D` | 複製 (連番インクリメント) | KiCad `Insert` に相当 |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo | macOS 標準 |
| `Cmd+A` | 全選択 | macOS 標準 |

#### 表示操作キー

| キー | 操作 |
|------|------|
| `Cmd+=` / `Cmd+-` | ズームイン / ズームアウト |
| `Cmd+0` | 全体表示 (Fit All) |
| `Space` | 全体表示 (LTspice と同一) |
| トラックパッドピンチ | ズーム |
| トラックパッドスクロール | パン |

#### シミュレーション操作キー

| キー | 操作 | 根拠 |
|------|------|------|
| `Cmd+R` | シミュレーション実行 | Xcode の "Run" と同一 |
| `Cmd+.` | シミュレーション停止 | Xcode の "Stop" と同一 |

### 2.3 操作詳細

#### 選択

- **シングルクリック**: オブジェクト選択。何もない場所をクリックで選択解除
- **Shift+クリック**: 選択に追加/除外(トグル)
- **範囲選択**: 左→右ドラッグで完全包含選択、右→左ドラッグで接触選択 (KiCad 方式)
- **ピンクリック**: 親コンポーネントを選択

#### 配線 (Wire)

- `W` でワイヤーモード開始
- **2 クリック方式**: 1 クリック目で始点、2 クリック目で終点を確定
- ピン近傍 (`gridSize * 1.5` 以内) は自動スナップし PinReference を設定
- 既存ワイヤー中間への接続時はワイヤーを自動分割 (`splitWiresAtEndpoints`)
- ワイヤー配置後にジャンクション自動再計算 (`recomputeJunctions`)
- `Esc` で配線キャンセル (`cancelPendingWire`)

> **計画中**: 多頂点ワイヤー、角度モード切替 (直交/フリーアングル)

#### 移動とドラッグ

- **ドラッグ (接続維持)**: Select モードでコンポーネントをドラッグすると、接続ワイヤーがラバーバンドで追従 (`moveSelection` + `updateConnectedWires`)。選択中のワイヤー自体は独立して移動する
- ドラッグ開始時に Undo 記録を自動実行
- グリッドスナップ適用

> **計画中**: `M` キーによる接続切断移動、`D` キーによる明示的ドラッグモード

#### ミラー

- `X`: 選択コンポーネントを X 軸(水平軸)で反転
- `Y`: 選択コンポーネントを Y 軸(垂直軸)で反転
- ミラー後に接続ワイヤーのエンドポイントを更新

#### コピー & ペースト

- `Cmd+C` (`copySelection`): 選択コンポーネント+ワイヤー+ラベルを ClipboardContent にコピー。アンカーポイント (選択中心) を記録
- `Cmd+V` (`paste`): カーソル位置にペースト。コンポーネント名は自動連番。ワイヤーの PinReference は新コンポーネント ID にリマップ。ペースト後にジャンクション再計算
- `Cmd+X` (`cutSelection`): コピー → 削除
- `Cmd+D` (`duplicate`): コピー → 20px オフセットでペースト

---

## 3. シミュレーション

CircuitStudio の最大の差別化要素。CoreSpice のインプロセス実行を活用する。

### 3.1 シミュレーションサービス

`SimulationService` は CoreSpice をブリッジし、パース → IR 変換 → コンパイル → デバイスバインド → 解析実行の全パイプラインを管理する。

```swift
protocol SimulationServiceProtocol: Sendable {
    func runSPICE(source:fileName:processConfiguration:onWaveformUpdate:) async throws -> SimulationResult
    func runAnalysis(source:fileName:processConfiguration:command:) async throws -> SimulationResult
    func cancel(jobID: UUID)
    func events(jobID: UUID) -> AsyncStream<SimulationEvent>
}
```

**対応解析タイプ**:

| 解析 | AnalysisCommand | 状態 |
|------|----------------|------|
| DC Operating Point | `.op` | 実装済み |
| トランジェント | `.tran(TranSpec)` | 実装済み (プログレッシブ波形ストリーミング付き) |
| AC 小信号 | `.ac(ACSpec)` | 実装済み |
| DC スイープ | `.dcSweep(DCSweepSpec)` | 実装済み |
| ノイズ | `.noise(NoiseSpec)` | 実装済み |
| 伝達関数 | `.tf(TFSpec)` | 実装済み |
| 極零 | `.pz(PZSpec)` | 実装済み |

**外部シミュレータフォールバック**: ProcessConfiguration で外部モデル (.lib/.inc) が検出された場合、`ExternalSpiceSimulator` 経由で ngspice を呼び出す。

### 3.2 イベントストリーミング

```swift
enum SimulationEvent: Sendable {
    case started
    case progress(Double, String)
    case waveformUpdate(WaveformData)
    case completed
    case failed(String)
    case cancelled
}
```

ジョブごとに `AsyncStream<SimulationEvent>` を提供する。トランジェント解析では 200ms 間隔のポーリングタスクで中間波形を `TransientProgressChannel` 経由でストリーミングする。

### 3.3 プログレッシブ波形レンダリング

トランジェント解析中に、タイムステップ完了コールバックを受信して波形を逐次描画する。

```
[TransientAnalysis.run()] ──► [onStepAccepted callback]
    → [TransientProgressChannel (lock-free バッファ)]
    → [ポーリングタスク (200ms 間隔)]
    → [TransientWaveformBuilder で WaveformData 構築]
    → [SimulationEvent.waveformUpdate 発行]
    → [WaveformViewModel.updateStreaming() で UI 更新]
```

`TransientWaveformBuilder` はタイムポイントとソリューション配列を逐次追加し、部分的な WaveformData を構築する。ポーリングタスクは解析完了後にも最終ドレインを行い、データ欠損を防ぐ。

### 3.4 計画中のライブ機能

以下は仕様として定義済みだが未実装:

- **Always-On DC Operating Point**: 編集操作に連動した自動バックグラウンド DC OP 実行
- **DC OP オーバーレイ表示**: ワイヤー上のノード電圧、コンポーネント上の動作点電流
- **IncrementalUpdate 活用**: パラメータ変更時のマトリクス部分再スタンプ
- **Click-to-Probe**: 回路図上のクリックで波形トレースを追加

---

## 4. 回路図レンダリング

### 4.1 グリッドシステム

| 項目 | 値 |
|------|-----|
| デフォルトグリッド | 10pt |
| 最小グリッド | 5pt |
| 表示 | ドットグリッド (デフォルト) / ラインクリッド / 非表示 |
| スナップ | 常時有効。`Cmd` ホールドでスナップ無効化 |

### 4.2 コンポーネントレンダリング

SwiftUI Canvas による描画。`DrawCommand` ベースのシンボル定義。

**選択状態**:
- 未選択: 標準色 (システムカラー)
- 選択中: アクセントカラー + 太線
- ホバー: 薄いハイライト

**ピン表示**:
- 未接続ピン: 赤丸 (直径 4pt)
- 接続済みピン: 非表示 (ワイヤーが接続を示す)
- NoConnect ピン: × マーク

### 4.3 ワイヤーレンダリング

- 標準: 1pt 線、システムカラー
- 選択中: 2pt 線、アクセントカラー
- ネット名表示: ラベル配置位置に表示
- ジャンクション: 塗りつぶし円 (直径 6pt)

### 4.4 DC OP オーバーレイ (計画中)

Always-On DC OP の結果を回路図上に表示する機能。未実装。

- ノード電圧: ワイヤー付近に `1.23V` のような小さなテキスト
- 分岐電流: コンポーネント付近に `→ 1.5mA` (矢印で方向表示)
- 色分け: 電圧レベルに応じたグラデーション (低=青、高=赤)
- 表示切替: ツールバーのトグルボタンまたは `V` キー

---

## 5. テストベンチとシミュレーション

### 5.1 テストベンチエディタ

回路図とは独立したシミュレーション設定 UI。

```
Testbench
├── analysisCommands: [AnalysisCommand]  // 実行する解析
├── stimuli: [Stimulus]                  // 入力信号定義
├── measurements: [Measurement]          // 計測式
└── options: SimulationOptions           // 収束パラメータ等
```

**解析コマンド UI**:
- プルダウンで解析タイプ選択 (DC OP / AC / Transient / DC Sweep / Noise / TF / PZ)
- タイプ別パラメータフォーム
- 複数解析の順次実行

**刺激信号 UI**:
- ソース名選択 (回路図上の V/I ソースから自動列挙)
- 波形タイプ選択 (DC / Pulse / Sine / AC)
- タイプ別パラメータフォーム
- 波形プレビュー

### 5.2 シミュレーション実行フロー

```
[Cmd+R] → [DesignService.validate()] → [エラーあれば表示して中断]
    → [NetlistGenerator.generate()] → [SimulationService.runAnalysis()]
    → [EventStream 購読] → [プログレス表示 + 波形ストリーミング]
    → [完了] → [WaveformViewer に自動遷移]
```

### 5.3 プログレス表示

SimulationEvent ストリームを活用:

| イベント | UI 表示 |
|---------|--------|
| `started` | シミュレーション開始表示 |
| `progress(Double, String)` | パーセント + ステップ名更新 |
| `waveformUpdate(WaveformData)` | 波形の逐次描画 (トランジェント) |
| `completed` | 完了表示、波形ビューアへ遷移 |
| `failed(String)` | エラーメッセージ表示 |
| `cancelled` | キャンセル表示 |

コンソールログは `SimulationConsoleView` でタイムスタンプ付きで表示する。

---

## 6. 波形ビューア

### 6.1 表示機能

| 機能 | 詳細 |
|------|------|
| トレース表示 | Swift Charts LineMark。複数 Y 軸対応 |
| カーソル | メインカーソル + デルタカーソル。値読み取り |
| ズーム | X 軸独立ズーム。ピンチジェスチャー + Cmd+=/- |
| パン | スクロールジェスチャー |
| 全体表示 | `Space` または Fit All ボタン |
| トレース管理 | サイドバーで表示/非表示切替、色変更 |
| デシメーション | Min/Max エンベロープ方式。ピーク保存 |

### 6.2 カーソル操作

- **シングルクリック**: メインカーソル設置。全トレースの値を読み取り
- **Shift+クリック**: デルタカーソル設置。メインカーソルとの差分表示
- **ドラッグ**: カーソル移動

### 6.3 工学表記

全数値を工学単位で表示:

| 倍率 | 接尾辞 |
|------|--------|
| 10^-15 | f |
| 10^-12 | p |
| 10^-9 | n |
| 10^-6 | u |
| 10^-3 | m |
| 10^0 | (なし) |
| 10^3 | k |
| 10^6 | M |
| 10^9 | G |

---

## 7. ERC (電気規則チェック)

### 7.1 リアルタイム検証

DesignService の検証を編集操作ごとに実行し、診断結果をリアルタイムに表示する。

```
[ドキュメント変更] → [デバウンス 200ms] → [DesignService.validate()]
    → [Diagnostic 配列更新] → [UI バッジ + インライン警告表示]
```

### 7.2 チェック項目

| チェック | 重要度 | 詳細 | 状態 |
|---------|--------|------|------|
| 空の設計 | Warning | コンポーネントが 0 個 | ✅ |
| 浮きピン | Warning | Wire.startPin/endPin で接続されていないピン | ✅ |
| GND 不在 | Warning | deviceKindID="ground" のコンポーネントが存在しない | ✅ |
| 重複コンポーネント名 | Error | 同じ名前のコンポーネントが複数存在 | ✅ |
| 必須パラメータ未設定 | Error | isRequired=true の ParameterSchema が未設定 | ✅ |
| パラメータ範囲外 | Error | ParameterSchema.range 外の値 | ✅ |
| 未知のデバイスタイプ | Info | DeviceCatalog に未登録の deviceKindID | ✅ |
| NoConnect 抑制 | — | NoConnect 型未実装のため浮きピン警告の抑制不可 | 未実装 |
| ショートサーキット | Warning | 電圧源が直接接続されている | 未実装 |

### 7.3 表示方法

- **DiagnosticsBar**: エラー数/警告数バッジ + 展開可能な詳細リスト
- **コンポーネント選択**: 診断項目クリックで該当コンポーネントを選択 (`componentID` 経由)
- **SchematicViewModel.validateDocument()**: DesignService.validate() を呼び出し diagnostics 配列を更新

---

## 8. デバイスカタログ

### 8.1 カテゴリ構成

| カテゴリ | デバイス |
|---------|---------|
| Passive | Resistor (R), Capacitor (C), Inductor (L) |
| Source | Voltage Source (V), Current Source (I) |
| Semiconductor | Diode (D), NPN BJT (Q), PNP BJT (Q), NMOS L1/L2/L3 (M), PMOS L1/L2/L3 (M) |
| Controlled | VCVS (E), VCCS (G), CCVS (H), CCCS (F) |
| Special | Ground (GND シンボル), Terminal (PORT — 計測対象ネット指定) |

> MOSFET は SPICE レベル (L1=Shichman-Hodges, L2=Grove-Frohman, L3=Semi-empirical) ごとに別デバイスとして定義。各レベルに `MOSFETModelPreset` を提供する。

### 8.2 パラメータ分類

DeviceKind のパラメータは 2 種類に分類される:

- **インスタンスパラメータ** (`isModelParameter: false`): SPICE インスタンス行に出力 (例: W, L)
- **モデルパラメータ** (`isModelParameter: true`): `.model` カードに出力 (例: vto, kp, bf)

### 8.3 拡張性

DeviceCatalog はプロトコルベースの登録制。将来的にユーザー定義デバイスを追加可能:

```swift
let catalog = DeviceCatalog.standard()
catalog.register(myCustomDevice)
```

---

## 9. 感度解析ヒント

CoreSpice の SensitivityAnalysis を活用し、PropertyInspector にパラメータ感度情報を表示する。

### 9.1 感度ヒント表示

DC OP が完了した後、バックグラウンドで感度解析を実行:

```
[DC OP 完了] → [SensitivityAnalysis 実行] → [パラメータ別感度係数計算]
    → [PropertyInspector に感度バー表示]
```

**表示例**:
```
R1 抵抗値: [=====10kΩ=====]  感度: ████░░ High
R2 抵抗値: [=====4.7kΩ====]  感度: █░░░░░ Low
```

赤いバーが長いパラメータは出力に大きく影響することを示す。回路の最適化においてどのパラメータを精密に選定すべきかのガイダンスとなる。

---

## 10. UI レイアウト

### 10.1 メインウィンドウ

```
┌───────────────────────────────────────────────────────┐
│  ■ CircuitStudio           [▶ Run] [⏹ Stop]  [V DC] │  ← ツールバー
├────────┬──────────────────────────────┬───────────────┤
│        │                              │               │
│  File  │     Schematic Canvas         │  Inspector    │
│  Nav   │                              │               │
│        │     [DC OP Overlay]          │  Properties   │
│        │                              │  Sensitivity  │
│        │                              │               │
│        ├──────────────────────────────┤               │
│        │                              │               │
│        │     Waveform Viewer          │  Trace List   │
│        │     [Progressive Render]     │  Cursor Val   │
│        │                              │               │
├────────┴──────────────────────────────┴───────────────┤
│  ⚠ 2 Warnings  ❌ 0 Errors  │  DC OP: converged     │  ← ステータスバー
└───────────────────────────────────────────────────────┘
```

### 10.2 パネル構成

| パネル | 位置 | 内容 |
|--------|------|------|
| File Navigator | 左サイドバー | プロジェクトファイルツリー |
| Schematic Canvas | メイン上部 | 回路図編集。DC OP オーバーレイ |
| Waveform Viewer | メイン下部 | 波形表示。プログレッシブレンダリング |
| Inspector | 右サイドバー | コンテキスト依存(Properties / Traces / Sensitivity) |
| Component Palette | フローティング | カテゴリ別デバイス一覧。展開/折りたたみ |
| Diagnostics | ボトムパネル(トグル) | ERC 結果一覧 |

### 10.3 コンポーネントパレット

カテゴリ別にデバイスを表示。DeviceCatalog から動的に生成。

- 展開/折りたたみアニメーション
- カテゴリヘッダーにアイコン
- デバイスアイテムにシンボルプレビュー
- クリックで配置モードに遷移
- ドラッグ&ドロップで直接配置 (将来)

---

## 11. ファイルフォーマット

### 11.1 プロジェクト構成

```
MyCircuit.circuitstudio/
├── project.json              // プロジェクトメタデータ
├── schematics/
│   ├── main.schematic.json   // SchematicDocument (JSON)
│   └── power.schematic.json  // 階層設計用 (将来)
├── testbenches/
│   └── default.testbench.json // Testbench (JSON)
├── results/
│   └── run_001.waveform       // WaveformData (バイナリ)
└── library/
    └── custom_devices.json    // ユーザー定義デバイス (将来)
```

### 11.2 エクスポート

| 形式 | 内容 |
|------|------|
| SPICE Netlist (.cir) | 標準 SPICE ネットリスト |
| Waveform RAW (.raw) | CoreSpice RAWExporter |
| Waveform CSV (.csv) | CoreSpice CSVExporter |
| Waveform PSF (.psf) | CoreSpice PSFExporter |
| PDF | 回路図印刷 (将来) |

### 11.3 インポート

| 形式 | 内容 |
|------|------|
| SPICE Netlist (.cir, .sp, .net) | SPICEParser による読み込み |

---

## 12. 実装ロードマップ

### Phase 1: 基盤 (Essential) — 完了

最低限のエディタとして機能するために必要な機能。

| 機能 | 状態 | 備考 |
|------|------|------|
| Undo/Redo | ✅ 完了 | UndoStack (スナップショット方式, maxDepth=100) |
| コピー & ペースト | ✅ 完了 | ClipboardContent, PinReference リマップ対応 |
| カット & 複製 | ✅ 完了 | cutSelection, duplicate (20px オフセット) |
| ミラー (X/Y) | ✅ 完了 | mirrorSelectionX/Y, ワイヤー端点自動更新 |
| 回転 (90° CW) | ✅ 完了 | rotateSelection, ワイヤー端点自動更新 |
| 範囲選択 | ✅ 完了 | selectInRect (enclosedOnly=左→右, intersect=右→左) |
| Shift+クリック複数選択 | ✅ 完了 | toggleSelection |
| 全選択 | ✅ 完了 | selectAll |
| グリッドスナップ | ✅ 完了 | デフォルト 10pt |
| ピンスナップ | ✅ 完了 | snapToPin (gridSize * 1.5 以内) |
| 全体表示 (Fit All) | ✅ 完了 | fitAll (contentBounds + margin) |

### Phase 2: 接続性 (Connectivity) — 一部完了

| 機能 | 状態 | 備考 |
|------|------|------|
| ジャンクション (自動算出) | ✅ 完了 | recomputeJunctions (3+ 端点で自動生成) |
| ワイヤー自動分割 | ✅ 完了 | splitWiresAtEndpoints (T 字接合対応) |
| PinReference ベースの接続追跡 | ✅ 完了 | Wire.startPin/endPin |
| ラバーバンドワイヤー追従 | ✅ 完了 | updateConnectedWires |
| ジャンクション手動配置 | 未実装 | EditTool.junction 未追加 |
| NoConnect フラグ | 未実装 | NoConnect 型未定義 |
| PowerSymbol (VCC, VDD, VSS) | 未実装 | 現在は Ground/Terminal コンポーネントで代替 |
| ワイヤー角度モード (直交/フリー) | 未実装 | |

### Phase 3: シミュレーション (Simulation) — 大部分完了

| 機能 | 状態 | 備考 |
|------|------|------|
| SimulationService (7 解析タイプ) | ✅ 完了 | OP, Tran, AC, DC Sweep, Noise, TF, PZ |
| プログレッシブ波形レンダリング | ✅ 完了 | TransientProgressChannel + 200ms ポーリング |
| イベントストリーミング | ✅ 完了 | AsyncStream\<SimulationEvent\> |
| キャンセル対応 | ✅ 完了 | CancellationToken |
| 外部 SPICE フォールバック | ✅ 完了 | ExternalSpiceSimulator (ngspice) |
| プロセスコーナー対応 | ✅ 完了 | ProcessConfiguration + CornerSet |
| Always-On DC OP | 未実装 | 自動バックグラウンド実行 |
| DC OP オーバーレイ表示 | 未実装 | |
| IncrementalUpdate 活用 | 未実装 | CoreSpice 側は対応済み |
| Click-to-Probe | 未実装 | |

### Phase 4: 高度な機能 (Advanced)

| 機能 | 状態 | 備考 |
|------|------|------|
| ERC (DesignService.validate) | ✅ 完了 | 6 チェック項目 (ピン未接続, GND 不在, 重複名, etc.) |
| 診断パネル (DiagnosticsBar) | ✅ 完了 | エラー/警告バッジ + 詳細リスト |
| デバイスカタログ | ✅ 完了 | BuiltInDevices (Passive, Source, Semiconductor, Controlled) |
| MOSFET モデルプリセット | ✅ 完了 | L1/L2/L3 レベル対応 |
| テストベンチモデル | ✅ 完了 | Testbench + AnalysisCommand + Stimulus |
| Experiment モデル | ✅ 完了 | MonteCarloSpec + SweepSpec + CornerSet |
| MiniMap | ✅ 完了 | MiniMapView + クリックナビゲーション |
| 感度解析ヒント | 未実装 | |
| 階層設計 | 未実装 | |
| テストベンチエディタ UI | 未実装 | モデルのみ実装済み |
| PDF エクスポート | 未実装 | |

### Phase 5: レイアウト (Layout) — 基盤完了

| 機能 | 状態 | 備考 |
|------|------|------|
| LayoutCore (データモデル) | ✅ 完了 | Document, Cell, Instance, Net, Pin, 制約 |
| LayoutTech (PDK/テクノロジー) | ✅ 完了 | TechDatabase, LayerDefinition, ViaDefinition |
| LayoutVerify (インデザイン DRC) | ✅ 完了 | 8 種類のルールチェック |
| LayoutIO (シリアライゼーション) | ✅ 完了 | JSON ネイティブ, 外部フォーマット拡張可能 |
| LayoutIntegration (外部ツール連携) | ✅ 完了 | ExternalSignoffRunner, CommandLineLayoutConverter |
| LayoutEditor (UI) | ✅ 完了 | Canvas, ToolPalette, LayerList, ViolationList |
| GDSII/OASIS ネイティブ I/O | 未実装 | LayoutFormatConverter で拡張可能 |
| スケマティック連携 (SDL) | 未実装 | |
| RC/EM/IR 抽出 | 未実装 | |

---

## 13. レイアウトサブシステム

半導体 IC のカスタム/アナログレイアウト編集機能。詳細要件は `semiconductor-layout-tool-spec.md` を参照。

### 13.1 モジュール構成

```
LayoutCore ─────────────────────────────────────
  │                                              │
  ├── LayoutTech (PDK/テクノロジールール)          │
  │     │                                        │
  │     ├── LayoutVerify (インデザイン DRC)        │
  │     │                                        │
  │     ├── LayoutIO (ファイル入出力)              │
  │     │                                        │
  │     └── LayoutIntegration (外部ツール連携)     │
  │           │                                  │
  └───────────┴── LayoutEditor (UI)              │
```

### 13.2 LayoutCore — データモデル

階層的レイアウトドキュメントモデル。DBU 整数座標ベース。

```
LayoutDocument
├── cells: [LayoutCell]              // セルライブラリ
├── topCellID: UUID?                 // トップセル参照
└── units: LayoutUnits               // DBU 設定 (precision, userUnit)

LayoutCell
├── shapes: [LayoutShape]            // 形状 (レイヤ, ジオメトリ, ネット)
├── vias: [LayoutVia]                // ビア配置
├── labels: [LayoutLabel]            // テキストラベル
├── pins: [LayoutPin]                // ピン定義 (role: signal/power/ground/gate/source/drain/bulk)
├── instances: [LayoutInstance]       // 子セルインスタンス (変換行列付き)
├── nets: [LayoutNet]                // ネット定義
└── constraints: [LayoutConstraint]   // アナログ制約
```

**ジオメトリ型**: LayoutRect, LayoutPolygon, LayoutPath — `LayoutGeometry` enum で統合

**変換**: LayoutTransform (translation + LayoutRotation (0/90/180/270°) + mirror)

**制約型**:
- `LayoutSymmetryConstraint` — 対称配置 (水平/垂直軸)
- `LayoutMatchingConstraint` — デバイスマッチング (最大長/幅ミスマッチ指定)
- `LayoutCommonCentroidConstraint` — 共通セントロイド配置 (パターン指定)
- `LayoutInterdigitatedConstraint` — インターデジット配置 (パターン指定)

**編集**: `LayoutDocumentEditor` がトランザクション単位の Undo/Redo を提供 (LayoutUndoStack, maxDepth=100)

### 13.3 LayoutTech — テクノロジーデータベース

```swift
struct LayoutTechDatabase: Sendable, Codable {
    var name: String
    var units: LayoutUnits
    var gridResolution: Double
    var layers: [LayoutLayerDefinition]     // GDS layer/datatype, 表示色, 優先方向
    var viaDefinitions: [LayoutViaDefinition]  // カット層, 上下層, サイズ, エンクロージャ
    var layerRules: [LayoutLayerRuleSet]    // minWidth, minSpacing, minArea, 密度範囲
    var antennaRules: [LayoutAntennaRule]   // アンテナ比率制限
}
```

`LayoutTechDatabase.standard()` で 2 層 (M1/M2/VIA1) のサンプル PDK を提供。

### 13.4 LayoutVerify — インデザイン DRC

`LayoutDRCService` が以下の 8 種類のルールチェックを実行:

| チェック | LayoutViolationKind |
|---------|-------------------|
| 最小幅 | `.minWidth` |
| 最小間隔 | `.minSpacing` |
| 最小面積 | `.minArea` |
| ビアエンクロージャ | `.enclosure` |
| レイヤ密度 (min/max) | `.density` |
| ショート (異ネット重畳) | `.overlapShort` |
| オープン (未接続ネット) | `.disconnectedOpen` |
| アンテナ比率 | `.antenna` |

接続性解析に `LayoutUnionFind` を使用。

### 13.5 LayoutIO — ファイル入出力

- **ネイティブ**: JSON (LayoutDocumentSerializer, pretty-printed + sorted keys)
- **拡張**: `LayoutFormatConverter` プロトコルで GDS/OASIS/LEF/DEF/ODB++ をサポート可能
- **CLI 変換**: `CommandLineLayoutConverter` がテンプレート変数 ({input}, {output}) で外部ツール呼び出し

### 13.6 LayoutIntegration — 外部ツール連携

- `ExternalToolConfiguration` — ドキュメント/テクノロジーのインポート/エクスポート設定
- `ExternalToolCommand` — コマンドライン実行 (引数テンプレート)
- `ExternalSignoffRunner` — 外部サインオフツール実行 + 出力キャプチャ
- `SignoffReport` — 成功/失敗ステータス + ログパス

### 13.7 LayoutEditor — UI

```
┌──────────┬──────────────────────┬──────────────┐
│  Tool    │                      │  Violation   │
│  Palette │    Layout Canvas     │  List        │
│          │                      │              │
│  ▪ Select│    [Grid + Shapes]   │  ⚠ minWidth  │
│  ▪ Rect  │    [Layer colors]    │  ⚠ spacing   │
│  ▪ Path  │    [Selection HL]    │              │
│  ▪ Via   │                      ├──────────────┤
│  ▪ Label │                      │  Layer List  │
│  ▪ Pin   │                      │  ■ M1 (blue) │
│          │                      │  ■ M2 (red)  │
└──────────┴──────────────────────┴──────────────┘
```

**ツールモード**: select, rectangle, path, via, label, pin

---

## 14. プロセスコンフィグレーション

### 14.1 ProcessTechnology

```swift
struct ProcessTechnology: Sendable, Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var version: String?
    var foundry: String?
    var defaultTemperature: Double
    var includePaths: [String]
    var libraries: [ProcessLibrary]
    var globalParameters: [String: Double]
    var cornerSet: CornerSet
    var defaultCornerID: UUID?
}
```

### 14.2 ProcessConfiguration

シミュレーション実行時の設定。テクノロジー、コーナー、インクルードパス、パラメータオーバーライドを統合する。

```swift
struct ProcessConfiguration: Sendable, Codable, Hashable {
    var technology: ProcessTechnology?
    var cornerID: UUID?
    var includePaths: [String]
    var parameterOverrides: [String: Double]
    var temperatureOverride: Double?
    var resolveIncludes: Bool
}
```

外部モデルライブラリ (.lib/.inc) が検出された場合、自動的に ngspice 経由の外部シミュレーションにフォールバックする。

### 14.3 Experiment

シミュレーション実験の完全な記録。再現性のためにハッシュを保持する。

```swift
struct Experiment: Sendable, Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var designID: UUID
    var testbenchID: UUID
    var cornerSet: CornerSet?
    var sweepSpec: SweepSpec?          // パラメータスイープ定義
    var monteCarloSpec: MonteCarloSpec? // モンテカルロ定義 (iterations, seed, distribution)
    var tags: [String]
    var note: String
}
```

---

## 付録 A: 競合ツールとのポジショニング

```
                    PCB フロー指向
                        ▲
                        │
           Altium ●     │     ● OrCAD
                        │
           KiCad ●      │
                        │
   ────────────────────────────────────►  操作の複雑さ
                        │
                ● Qucs-S │
                        │
         ● CircuitStudio│
                        │
           LTspice ●    │
                        │
                    シミュレーション指向
```

CircuitStudio は LTspice のシミュレーション指向の思想を継承しつつ、ライブフィードバックとネイティブ macOS 体験で差別化する。PCB フロー(フットプリント割当、基板設計)は対象外とする。

## 付録 B: 用語集

| 用語 | 定義 |
|------|------|
| DC OP | DC Operating Point。回路の静的動作点 |
| IncrementalUpdate | マトリクス全体を再構築せずに変更パラメータのみ再スタンプする最適化 |
| MNA | Modified Nodal Analysis。回路方程式の標準定式化 |
| Newton-Raphson | 非線形方程式の反復求解法 |
| Rubber Banding | コンポーネント移動時にワイヤーが追従する動作 |
| Gmin Stepping | 収束困難時にコンダクタンスを段階的に減少させる手法 |
| LTE | Local Truncation Error。トランジェント解析のステップサイズ制御基準 |
| ERC | Electrical Rules Check。回路図の電気的整合性検証 |
| DRC | Design Rule Check。レイアウトの物理ルール検証 |
| DBU | Database Unit。レイアウト座標系の最小単位 |
| PDK | Process Design Kit。ファウンドリ提供のルール/モデルセット |
| PinReference | コンポーネント ID + ポート ID の組。ワイヤー端点の明示的接続先 |
| CornerSet | プロセスコーナー (TT, FF, SS, SF, FS) の集合 |
| SDL | Schematic-Driven Layout。スケマティック駆動のレイアウト設計 |
