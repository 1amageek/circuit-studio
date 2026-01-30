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

```
┌─────────────────────────────────────────────────────┐
│                   CircuitStudio                      │
│                                                     │
│  ┌──────────────┐  ┌───────────┐  ┌──────────────┐ │
│  │  Schematic   │  │ Testbench │  │  Waveform    │ │
│  │  Editor      │──│ Editor    │──│  Viewer      │ │
│  └──────┬───────┘  └─────┬─────┘  └──────▲───────┘ │
│         │                │               │         │
│  ┌──────▼────────────────▼───────────────┤         │
│  │           Reactive Pipeline            │         │
│  │                                        │         │
│  │  SchematicDocument                     │         │
│  │       │                                │         │
│  │  NetExtractor ──► ExtractedNets        │         │
│  │       │                                │         │
│  │  NetlistGenerator ──► SPICE Source     │         │
│  │       │                                │         │
│  │  ┌────▼─────────────────────────┐      │         │
│  │  │        CoreSpice (in-process)│      │         │
│  │  │                              │      │         │
│  │  │  Parse → Lower → Compile ────┤      │         │
│  │  │       │                      │      │         │
│  │  │  IncrementalUpdate ──────────┤      │         │
│  │  │       │                      │      │         │
│  │  │  Analysis.run() ─────────────┤      │         │
│  │  │       │            ▲         │      │         │
│  │  │  EventStream ──────┘         │      │         │
│  │  │       │                      │      │         │
│  │  │  WaveformData ───────────────┼──────┘         │
│  │  └──────────────────────────────┘                │
│  └──────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────┘
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
├── junctions: [Junction]           // 明示的ジャンクション (NEW)
├── noConnects: [NoConnect]         // 未接続フラグ (NEW)
├── selection: Set<UUID>            // 選択状態
└── powerSymbols: [PowerSymbol]     // 電源シンボル (NEW)
```

### 1.2 新規型

**Junction** — ワイヤー交差点での明示的接続。

```swift
struct Junction: Identifiable, Sendable {
    let id: UUID
    var position: CGPoint
}
```

KiCad と同様にジャンクションを明示配置する方式を採用する。ワイヤーが既存ワイヤー上で開始/終了する場合は自動配置する。

**NoConnect** — ピンの意図的未接続マーク。

```swift
struct NoConnect: Identifiable, Sendable {
    let id: UUID
    var position: CGPoint
}
```

ERC でピン未接続警告を抑制するために使用する。

**PowerSymbol** — グローバル電源ネット。

```swift
struct PowerSymbol: Identifiable, Sendable {
    let id: UUID
    var netName: String      // "VCC", "VDD", "GND", "VSS" 等
    var position: CGPoint
    var symbolStyle: PowerSymbolStyle  // .bar, .arrow, .circle, .ground
}
```

Ground コンポーネントを PowerSymbol に統合する。全シート共通のグローバルスコープを持つ。

### 1.3 Undo/Redo

```swift
struct UndoManager {
    private var undoStack: [SchematicDocument]
    private var redoStack: [SchematicDocument]
    private let maxDepth: Int = 100

    mutating func record(_ document: SchematicDocument)
    mutating func undo() -> SchematicDocument?
    mutating func redo() -> SchematicDocument?
}
```

ドキュメント全体のスナップショット方式を採用する。SchematicDocument は値型(struct)であるため、コピーコストは低い。Copy-on-Write により実際のメモリコピーは変更のあった配列のみに発生する。

---

## 2. 編集操作

### 2.1 ツールモード

```swift
enum EditTool: Sendable {
    case select
    case place(String)           // デバイス配置
    case wire                    // ワイヤー描画
    case label                   // ネットラベル配置
    case junction                // ジャンクション配置 (NEW)
    case noConnect               // NoConnect 配置 (NEW)
    case power(PowerSymbolStyle) // 電源シンボル配置 (NEW)
}
```

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
- クリックで頂点追加
- ダブルクリックまたは `Esc` でワイヤー終了
- ピン上でクリックすると自動接続して終了
- 既存ワイヤー上でのワイヤー開始/終了時にジャンクション自動配置
- 角度モード: 直交 (デフォルト)。`Shift+Space` でフリーアングルに切替

#### 移動とドラッグ

- **移動 (`M`)**: 選択オブジェクトを接続を切断して移動。ワイヤーは切断される
- **ドラッグ (`D`)**: 選択オブジェクトを接続を維持して移動。接続ワイヤーがラバーバンドで追従
- **直接ドラッグ**: Select モードでコンポーネントをドラッグすると自動的にドラッグ(接続維持)モードになる

#### ミラー

- `X`: 選択コンポーネントを X 軸(水平軸)で反転
- `Y`: 選択コンポーネントを Y 軸(垂直軸)で反転
- ミラー後に接続ワイヤーのエンドポイントを更新

#### コピー & ペースト

- `Cmd+C`: 選択オブジェクト(コンポーネント+接続ワイヤー+ラベル)をクリップボードにコピー
- `Cmd+V`: カーソル位置にペースト。コンポーネント名は自動的に新しい連番を付与
- `Cmd+D`: 選択をその場で複製。10px オフセットして配置。連番インクリメント

---

## 3. ライブシミュレーション

CircuitStudio の最大の差別化要素。CoreSpice のインプロセス実行と IncrementalUpdate を活用する。

### 3.1 Always-On DC Operating Point

回路が有効な状態(GND 存在、接続完了)になると、バックグラウンドで DC OP を自動実行する。

```
[ユーザー編集] → [デバウンス 300ms] → [ネット抽出] → [ネットリスト生成]
    → [CoreSpice コンパイル] → [DC OP 実行] → [結果オーバーレイ表示]
```

**表示方法**:
- ワイヤー上にノード電圧を薄く表示 (ホバーで詳細)
- コンポーネント上に動作点電流を表示 (オプション)
- 異常値(過電圧、過電流)は赤色でハイライト

**実装**:
```swift
// SchematicViewModel 拡張
func onDocumentChanged() {
    debounce(300ms) {
        let netlist = netlistGenerator.generate(from: document)
        let result = try await simulationService.runDCOP(netlist)
        self.operatingPoint = result  // @Observable → Canvas 再描画
    }
}
```

### 3.2 インタラクティブパラメータチューニング

PropertyInspector でパラメータ値を変更すると、IncrementalUpdate により瞬時に再シミュレーションする。

```
[スライダー操作] → [IncrementalUpdate(R1: 10kΩ → 15kΩ)] → [DC OP 再計算]
    → [波形更新] (フルリコンパイル不要)
```

**実装の鍵**: CoreSpice の `IncrementalUpdate` 構造体により、変更デバイスのスタンプのみを再計算する。マトリクストポロジーは保持される。

### 3.3 プログレッシブ波形レンダリング

トランジェント解析中に、タイムステップ完了イベントを受信して波形を逐次描画する。

```
[Analysis.run()] ──► [TimeStepCompleted event] ──► [WaveformData 部分更新]
                                                        │
                                                  [チャート追記描画]
```

CoreSpice の `AnalysisEvent.timeStepCompleted` イベントを購読し、`WaveformViewModel` にストリーミングで結果を追加する。

### 3.4 Click-to-Probe

LTspice のクリック・ツー・プローブを発展させる。

**シミュレーション実行後の回路図操作**:
- **ノードクリック**: 波形ビューアにそのノードの電圧トレースを追加
- **コンポーネントクリック**: そのコンポーネントを流れる電流トレースを追加
- **Option+クリック**: 電力波形 (V × I) を追加
- **2 点間ドラッグ**: 差動電圧 V(A) - V(B) を追加

LTspice との差: シミュレーション後も編集操作が可能(モード切替不要)。プローブはツールバーの Probe ボタンまたは `T` キーで有効化。

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

### 4.4 DC OP オーバーレイ (Live Simulation)

Always-On DC OP の結果を回路図上に表示:

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

CoreSpice の AnalysisEvent を活用:

| イベント | UI 表示 |
|---------|--------|
| `analysisStarted` | プログレスバー開始 |
| `progressUpdate` | パーセント更新 |
| `newtonIterationStarted` | (詳細モード) 反復回数表示 |
| `newtonConvergenceFailure` | 警告アイコン + 収束失敗メッセージ |
| `timeStepCompleted` | 波形ポイント追加 |
| `timeStepRejected` | (詳細モード) ステップ棄却表示 |
| `sweepPointFinished` | スイープ進捗更新 |
| `analysisFinished` | プログレスバー完了 |

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

| チェック | 重要度 | 詳細 |
|---------|--------|------|
| 浮きピン | Warning | 未接続かつ NoConnect なしのピン |
| GND 不在 | Error | Ground / GND PowerSymbol が存在しない |
| 重複コンポーネント名 | Error | 同じ名前のコンポーネントが複数存在 |
| 必須パラメータ未設定 | Error | isRequired=true のパラメータが未設定 |
| パラメータ範囲外 | Error | ParameterSchema.range 外の値 |
| 未知のデバイスタイプ | Info | DeviceCatalog に未登録の deviceKindID |
| ショートサーキット | Warning | 電圧源が直接接続されている |
| 出力ピン同士の接続 | Warning | 出力ポート同士がネットで接続 (将来) |

### 7.3 表示方法

- **ステータスバー**: エラー数/警告数バッジ
- **インライン表示**: 問題コンポーネントにアイコンオーバーレイ (赤=Error、黄=Warning)
- **診断パネル**: クリックで問題箇所へジャンプ

---

## 8. デバイスカタログ

### 8.1 カテゴリ構成

| カテゴリ | デバイス |
|---------|---------|
| Passive | Resistor (R), Capacitor (C), Inductor (L) |
| Source | Voltage Source (V), Current Source (I) |
| Semiconductor | Diode (D), NPN BJT (Q), PNP BJT (Q), NMOS (M), PMOS (M) |
| Controlled | VCVS (E), VCCS (G), CCVS (H), CCCS (F) |
| Power | GND, VCC, VDD, VSS (PowerSymbol として統合) |

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

### Phase 1: 基盤 (Essential)

最低限のエディタとして機能するために必要な機能。

| 機能 | 優先度 | 依存 |
|------|--------|------|
| Undo/Redo | Critical | SchematicDocument 値型 |
| コピー & ペースト | Critical | Undo/Redo |
| ミラー (X/Y) | High | — |
| キーボードショートカット拡充 (W, P, L, M, D, X, Y) | High | EditTool 拡張 |
| 範囲選択 (左→右/右→左) | High | — |
| Shift+クリック複数選択 | High | — |

### Phase 2: 接続性 (Connectivity)

正確な回路接続を保証する機能。

| 機能 | 優先度 | 依存 |
|------|--------|------|
| ジャンクション (自動+手動配置) | High | Junction 型 |
| NoConnect フラグ | Medium | NoConnect 型 |
| PowerSymbol (VCC, VDD, VSS) | Medium | PowerSymbol 型 |
| ワイヤー角度モード (直交/フリー) | Medium | — |
| クリックでワイヤーモード配線 | Medium | Wire モード改修 |

### Phase 3: ライブシミュレーション (Live Feedback)

CircuitStudio の差別化要素。

| 機能 | 優先度 | 依存 |
|------|--------|------|
| Always-On DC OP | High | NetlistGenerator + SimulationService |
| DC OP オーバーレイ表示 | High | Always-On DC OP |
| プログレッシブ波形レンダリング | Medium | AnalysisEvent 購読 |
| インタラクティブパラメータチューニング | Medium | IncrementalUpdate |
| シミュレーションプログレス表示 | Medium | AnalysisEvent 購読 |
| Click-to-Probe | Medium | 波形ビューア + HitTest |

### Phase 4: 高度な機能 (Advanced)

プロフェッショナル向け機能。

| 機能 | 優先度 | 依存 |
|------|--------|------|
| リアルタイム ERC | Medium | DesignService + デバウンス |
| 感度解析ヒント | Low | SensitivityAnalysis |
| 階層設計 | Low | 新規ドキュメントモデル |
| カスタムデバイス定義 | Low | DeviceCatalog 拡張 |
| テストベンチエディタ UI | Medium | Testbench モデル |
| SPICE インポート | Low | SPICEParser |
| PDF エクスポート | Low | — |

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
