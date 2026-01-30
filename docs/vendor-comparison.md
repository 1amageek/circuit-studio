# 回路エディターベンダー仕様比較

CircuitStudio の仕様策定にあたり、業界主要ツールの機能を調査・比較したドキュメント。

## 対象ツール

| ツール | ライセンス | 主目的 |
|--------|-----------|--------|
| KiCad Eeschema | OSS (GPL) | PCB 設計フロー |
| LTspice | 無料 (プロプライエタリ) | SPICE シミュレーション |
| Qucs-S | OSS (GPL) | SPICE シミュレーション |
| Altium Designer | 商用 (~$10K) | PCB 設計フロー |
| OrCAD Capture | 商用 (~$2K+) | PCB 設計フロー |

---

## 1. 編集操作

### 1.1 配置 (Place)

| ツール | 操作 | 詳細 |
|--------|------|------|
| KiCad | `A` | シンボル選択ダイアログ。名前・キーワード・説明でフィルタ。ワイルドカード・正規表現対応 |
| LTspice | `F2` | コンポーネント選択。頻用部品に専用キー: `R`(抵抗), `C`(容量), `L`(インダクタ), `D`(ダイオード), `G`(GND) |
| Qucs-S | 左サイドバーからドラッグ | カテゴリ別パレット。右クリックで配置中回転 |
| Altium | `P, P` | プレフィックスシーケンス。`Tab` で配置前にプロパティ編集可 |
| OrCAD | Place Part ダイアログ | `.olb` ライブラリからパーツ選択 |

### 1.2 配線 (Wire)

| ツール | 操作 | 角度モード | 特殊機能 |
|--------|------|-----------|---------|
| KiCad | `W` | フリー / 90° / 45° (`Shift+Space` で切替、`/` で反転) | ワイヤーが既存セグメントに接触すると自動分割 |
| LTspice | `F3` | 直交のみ | ワイヤーを 2 端子部品に通すと自動的に直列挿入される |
| Qucs-S | Insert → Wire | 直交のみ | 右クリックでコーナー方向変更 |
| Altium | `P, W` | 複数モード | — |
| OrCAD | Draw Wire | 直交 | Autowire: ピン間の自動配線 |

### 1.3 移動 / ドラッグ

全ツールが「移動」と「ドラッグ（接続維持）」を区別している:

| ツール | 移動 | ドラッグ (rubber banding) |
|--------|------|-------------------------|
| KiCad | `M` (接続切断) | `G` (接続維持) |
| LTspice | `F7` (接続切断) | `F8` (接続維持) |
| Qucs-S | Select モードでドラッグ | — |
| Altium | ドラッグ | — |
| OrCAD | ドラッグ | — |

### 1.4 回転 / ミラー

| ツール | 回転 | ミラー |
|--------|------|--------|
| KiCad | `R` | `X` (X 軸), `Y` (Y 軸) |
| LTspice | `Ctrl+R` | `Ctrl+E` |
| Qucs-S | 右クリック(配置中) / メニュー | メニュー |
| Altium | `Space` (配置中) | `X` / `Y` (配置中) |
| OrCAD | `R` | — |

### 1.5 コピー / Undo / Redo

| ツール | コピー | Undo | Redo |
|--------|--------|------|------|
| KiCad | `Ctrl+C/V`、`Insert`(連番インクリメント付き複製) | `Ctrl+Z` | `Ctrl+Y` |
| LTspice | `F6` (複製モード) | `F9` | `Ctrl+Y` |
| Qucs-S | `Ctrl+C/V/X` | `Ctrl+Z` | `Ctrl+Y` |
| Altium | `Ctrl+C/V`、`Ctrl+R`(ラバースタンプ) | `Ctrl+Z` | `Ctrl+Y` |
| OrCAD | `Ctrl+C/V`、ドラッグ中 `C` ホールドでコピー | `Ctrl+Z` | `Ctrl+Y` |

### 1.6 選択

| ツール | 方式 |
|--------|------|
| KiCad | 左→右: 完全包含選択、右→左: 接触選択。修飾キーで追加/除外/トグル。`Alt+4` で接続ワイヤー一括選択 |
| LTspice | クリック選択。シミュレーション後はクリックがプローブに変わる |
| Qucs-S | クリック / 範囲選択 |
| Altium | 標準 Windows 選択 |
| OrCAD | クリック / 範囲選択。`Ctrl+I` で選択フィルタ(オブジェクトタイプ制限) |

---

## 2. ネット / 配線モデル

### 2.1 接続ルール

| ツール | 接続条件 | ジャンクション |
|--------|---------|---------------|
| KiCad | 端点一致のみ | 明示配置が必須。交差ワイヤーはジャンクションなしで非接続。ワイヤー開始/終了が既存セグメント上なら自動配置 |
| LTspice | 端点一致 | T 接合で自動生成(ドット表示) |
| Qucs-S | 端点一致 | 端点一致ベース |
| Altium | 端点一致 | 明示 + 自動 |
| OrCAD | 端点一致 | 明示 + 自動 |

### 2.2 ラベルとスコープ

| ツール | ラベル種別 | スコープ |
|--------|-----------|---------|
| KiCad | Local Label | 単一シート内 |
| | Global Label | 全シート共通 |
| | Hierarchical Label | 子シート↔親シートの接続点 |
| | Power Symbol (VCC, GND) | 全シートグローバル |
| LTspice | Net Label (`F4`) | 全体(フラットスキーマ) |
| Qucs-S | Wire Label | ワイヤー上配置 |
| Altium | Net Label / Port / Power Port | 各スコープ |
| OrCAD | Net Alias / Port / Off-page Connector | 各スコープ |

**ネット命名優先順位 (KiCad)**:
Global Label > Power Symbol > Local Label > Hierarchical Label > Sheet Pin

### 2.3 バス

| ツール | バスサポート | 詳細 |
|--------|------------|------|
| KiCad | Vector Bus + Group Bus | `DATA[0..7]` (ベクタ)、`USB1{DP DM VBUS}` (グループ)。バスエイリアス定義可。ピンは直接接続不可(バスエントリ経由) |
| LTspice | なし | アナログ SPICE 特化のため非対応 |
| Qucs-S | なし | 同上 |
| Altium | Bus + Signal Harness | バスエントリ + 高度なシグナルハーネス |
| OrCAD | Bus + Bus Entry | 標準的なバスサポート |

### 2.4 電源 / GND / No-Connect

| ツール | 電源シンボル | No-Connect フラグ |
|--------|------------|------------------|
| KiCad | VCC, GND, PWR_FLAG 等。PWR_FLAG は ERC にパワーネット駆動を通知 | あり (ERC 警告抑制) |
| LTspice | Ground (`G` キー) のみ。電源は電圧源で代用 | なし |
| Qucs-S | Ground コンポーネント | なし |
| Altium | Power Port (グローバルスコープ) | あり |
| OrCAD | Power Symbol | あり |

---

## 3. コンポーネント / シンボルライブラリ

### 3.1 ライブラリ規模

| ツール | シンボル数 | 管理方式 |
|--------|----------|---------|
| KiCad | 数千 | 2 層テーブル(グローバル + プロジェクト)。`.kicad_sym` ファイル。配置時にスキーマへ埋め込みコピー |
| LTspice | ~800 | ファイルベース(`.asy` シンボル + `.sub`/`.lib`/`.mod` モデル) |
| Qucs-S | 数百 | カテゴリ別内蔵。外部 SPICE `.lib`/`.sub` インポート対応 |
| Altium | 数千+ | 統合データモデル(シンボル+フットプリント+3D+SPICE+データシート)。クラウド連携 |
| OrCAD | 数千+ | `.olb` バイナリ。CIS (Component Information System) でデータベース連携 |

### 3.2 カスタムシンボル作成

| ツール | 方式 |
|--------|------|
| KiCad | 統合シンボルエディタ。マルチユニット対応。ピン管理 GUI |
| LTspice | File → New Symbol。描画ツール(線、矩形、弧、円)+ ピン配置 |
| Qucs-S | GUI 対応 |
| Altium | 統合エディタ。Generic Component でプレースホルダ配置後に決定可 |
| OrCAD | ライブラリエディタ |

### 3.3 シンボル属性

LTspice のシンボル属性体系は SPICE シミュレーション向けに最適化されている:

- `Prefix`: コンポーネント種別識別子 (R, C, M, X 等)
- `ModelFile`: ライブラリファイル参照
- `SpiceModel`: モデル名
- `Value`: コンポーネント値

---

## 4. シミュレーション統合

### 4.1 シミュレーション対応状況

| 解析タイプ | KiCad (ngspice) | LTspice | Qucs-S (ngspice) | Altium | OrCAD (PSpice) |
|-----------|----------------|---------|------------------|--------|----------------|
| DC OP | Yes | Yes | Yes | Yes | Yes |
| AC | Yes | Yes | Yes | Yes | Yes |
| Transient | Yes | Yes | Yes | Yes | Yes |
| DC Sweep | Yes | Yes | Yes | Yes | Yes |
| Noise | Yes | Yes | Yes | — | Yes |
| Transfer Function | — | Yes | — | — | — |
| Pole-Zero | — | — | Yes | — | — |
| Fourier | — | — | Yes | — | — |
| Monte Carlo | — | Yes (.step) | Yes | — | Yes |
| S-Parameter | Yes | — | Yes | — | — |
| Harmonic Balance | — | — | Yes (Xyce) | — | — |

### 4.2 ワークフロー

**LTspice** (最もシンプル):
1. 回路図入力
2. SPICE ディレクティブを回路図上に配置 (`.tran`, `.ac` 等)
3. `Ctrl+B` でシミュレーション実行
4. ノードクリックで電圧波形、部品クリックで電流波形を表示

**KiCad**:
1. 回路図入力
2. シンボルに SPICE モデルをプロパティで割当
3. カスタム SPICE ディレクティブをアノテーションとして配置
4. 統合波形ビューアで結果表示

**Qucs-S**:
1. 回路図入力
2. シミュレーションタイプアイコンを回路図上に配置
3. パラメータ設定
4. 結果は回路図上のダイアグラムまたは別ページに表示

---

## 5. ERC (電気規則チェック)

### 5.1 チェック項目比較

| チェック項目 | KiCad | LTspice | Qucs-S | Altium | OrCAD |
|-------------|-------|---------|--------|--------|-------|
| 浮きピン検出 | Error | シミュレーション時 | シミュレーション時 | リアルタイム | 設定可 |
| 未接続チェック | Error | シミュレーション時 | シミュレーション時 | リアルタイム | 設定可 |
| 出力ピン同士の接続 | 設定可 | — | — | 設定可 | 設定可(ERC マトリクス) |
| 入力パワーピン未駆動 | Error (PWR_FLAG で解決) | — | — | Error | Error |
| バスエイリアス不整合 | Error (シート間) | — | — | — | — |
| 重複ネット名 | Warning | — | — | Warning | Warning |
| ピン種別マトリクス | あり | なし | なし | あり | あり |

### 5.2 実行タイミング

| ツール | タイミング |
|--------|----------|
| KiCad | 手動実行 (ERC ダイアログ) |
| LTspice | シミュレーション実行時に暗黙チェック |
| Qucs-S | シミュレーション実行時に暗黙チェック |
| Altium | リアルタイム (編集中に常時チェック) |
| OrCAD | 手動 + Dynamic ERC (OrCAD X) |

---

## 6. 階層設計

### 6.1 階層モデル

| ツール | モデル | 詳細 |
|--------|-------|------|
| KiCad | Flat / Simple / Complex | 各シートは独立 `.kicad_sch` ファイル。Complex = シート再利用。Hierarchy Navigator でツリー表示 |
| LTspice | Block / Subcircuit | Block (Symbol Type="Block"): 子スキーマの `.asc` + 対応 `.asy` を同ディレクトリに配置。Subcircuit (Symbol Type="Cell"): SPICE `.SUBCKT` 定義 |
| Qucs-S | Subcircuit | `.sch` に Subcircuit Port を追加で子回路化。Ground は自動的にサブ回路境界を越える。パラメータ化サブ回路対応 |
| Altium | Top-down / Bottom-up / Multi-channel | Device Sheet で IP 再利用。マルチチャネルで配線・配置のコピー。フラット↔階層変換ツール |
| OrCAD | Simple / Complex | 階層ブロック・ポート・ピンで接続。Hierarchy タブでツリー表示。`.DSN` 内に単一ルートモジュール |

### 6.2 接続メカニズム

| ツール | 親→子接続 | 子→親接続 |
|--------|----------|----------|
| KiCad | Sheet Pin (Import Hierarchical Pin) | Hierarchical Label |
| LTspice | シンボルピン(ピン順 = .SUBCKT ヘッダ順) | Net Label (`F4`) |
| Qucs-S | サブ回路インスタンスのポート | Subcircuit Port コンポーネント |
| Altium | Sheet Entry | Port |
| OrCAD | Hierarchical Pin | Hierarchical Port |

---

## 7. キーボードショートカット体系

### 7.1 KiCad — 単一キー中心

| キー | 操作 |
|------|------|
| `A` | シンボル配置 |
| `W` | ワイヤー描画 |
| `B` | バス描画 |
| `E` | プロパティ編集 |
| `M` | 移動 |
| `G` | ドラッグ(接続維持) |
| `R` | 回転 |
| `X` / `Y` | X 軸 / Y 軸ミラー |
| `U` / `V` / `F` | リファレンス / 値 / フットプリント インライン編集 |
| `Insert` | 連番インクリメント付き繰返し配置 |
| `Shift+Space` | ワイヤー角度モード切替 |
| `/` | ワイヤー方向反転 |
| `~` | ネットハイライト解除 |
| `Alt+4` | 接続ワイヤーセグメント一括選択 |

完全カスタマイズ可能 (Preferences → Hotkeys)。

### 7.2 LTspice — F キー + 専用キー

左手キーボード / 右手マウスに最適化された配置:

**F キー (オブジェクト操作)**:

| キー | 操作 |
|------|------|
| `F2` | コンポーネント配置 |
| `F3` | ワイヤーモード |
| `F4` | ネットラベル |
| `F5` | 削除 |
| `F6` | 複製 |
| `F7` | 移動 |
| `F8` | ドラッグ |
| `F9` | Undo |

**専用キー (頻用部品)**:

| キー | 部品 |
|------|------|
| `R` | 抵抗 |
| `C` | コンデンサ |
| `L` / `X` | インダクタ |
| `D` | ダイオード |
| `G` | グラウンド |

**Ctrl キー (アクション)**:

| キー | 操作 |
|------|------|
| `Ctrl+R` | 回転 |
| `Ctrl+E` | ミラー |
| `Ctrl+B` | シミュレーション開始 |
| `Ctrl+H` | シミュレーション停止 |
| `Ctrl+Y` | Redo |

**Shift キー (描画 / ズーム)**:

| キー | 操作 |
|------|------|
| `Shift+W` | グラフィカル線描画 |
| `Shift+R` | 矩形描画 |
| `Shift+A` | 弧描画 |
| `Shift+C` | 円描画 |
| `Shift+Z` | 範囲ズーム |
| `Space` | 全体表示 |

### 7.3 Altium — プレフィックスシーケンス

約 800 のショートカット。`P` プレフィックスで配置系操作:

| キー | 操作 |
|------|------|
| `P, W` | ワイヤー配置 |
| `P, P` | パーツ配置 |
| `P, J` | ジャンクション配置 |
| `P, N` | ネットラベル配置 |
| `P, T` | テキスト配置 |
| `P, O` | ポート配置 |
| `P, G` | パワーポート配置 |
| `Space` | 配置中回転 |
| `Tab` | 配置中プロパティ編集 |
| `G` | グリッド切替 |
| `Q` | mil/mm 切替 |
| `Ctrl+R` | ラバースタンプモード |

---

## 8. ファイルフォーマット

| ツール | スキーマファイル | シンボルファイル | 形式 |
|--------|---------------|---------------|------|
| KiCad | `.kicad_sch` | `.kicad_sym` | テキスト (S 式) |
| LTspice | `.asc` | `.asy` | ASCII テキスト |
| Qucs-S | `.sch` | `.sch` 内埋め込み | XML 風テキスト |
| Altium | `.SchDoc` | `.SchLib` | バイナリ / ASCII |
| OrCAD | `.DSN` | `.OLB` | バイナリ |

### エクスポート対応

| ツール | ネットリスト | 画像 / PDF | その他 |
|--------|------------|-----------|--------|
| KiCad | カスタム (Python/XSLT) | PDF, SVG, PostScript, HPGL | BOM 生成 |
| LTspice | `.net` (自動生成) | — | `.raw` (波形データ) |
| Qucs-S | SPICE ネットリスト | — | 波形データ |
| Altium | 多形式 | PDF, DXF | OrCAD / Eagle / KiCad インポート |
| OrCAD | 標準 + カスタム | PDF | EDIF, Altium 互換 |

---

## 9. 波形ビューア

### 9.1 機能比較

| 機能 | LTspice | KiCad | Qucs-S | Altium |
|------|---------|-------|--------|--------|
| クリック・ツー・プローブ | あり (回路図ノード/部品クリック) | — | — | — |
| カーソル | 2 カーソル + デルタ表示 | 基本カーソル | マーカー | — |
| 数式演算 | あり (`V(out)/V(in)` 等) | — | Nutmeg 式 | — |
| FFT | あり | — | — | — |
| 複数ペイン | あり (電圧/電流分離) | — | ダイアグラム | — |
| ズーム | 範囲選択 / マウスホイール | マウスホイール | — | — |
| 出力形式 | `.raw` (バイナリ) | — | — | — |

### 9.2 LTspice のプローブ操作

シミュレーション実行後、回路図上での操作がプローブモードに切替わる:

- **ノードクリック**: 電圧波形を追加
- **部品クリック**: 電流波形を追加
- **Alt+クリック**: 電力波形を追加
- **ワイヤー右ドラッグ**: 差動電圧

---

## 10. 設計パターンと業界慣行

### 10.1 グリッドシステム

| ツール | デフォルトグリッド | 単位 |
|--------|-----------------|------|
| KiCad | 50 mil (1.27 mm) | mil / mm 切替可 |
| LTspice | 設定可能 | — |
| Altium | 設定可能 | mil / mm 切替可 (`Q` キー) |

### 10.2 ツールモード vs モードレス

| パターン | ツール | 説明 |
|---------|--------|------|
| モーダル | LTspice, Qucs-S | ツール選択→操作→ツール解除。明確だが切替コスト |
| セミモーダル | KiCad | 単一キーでツール即起動。`Esc` で戻る。高速 |
| モードレス | Altium | プレフィックスシーケンスで直接操作。学習コスト高いが最速 |

### 10.3 コンポーネント命名規則

SPICE 標準のプレフィックス規約:

| プレフィックス | デバイス |
|--------------|---------|
| R | 抵抗 |
| C | コンデンサ |
| L | インダクタ |
| V | 電圧源 |
| I | 電流源 |
| D | ダイオード |
| Q | BJT (NPN/PNP) |
| M | MOSFET |
| J | JFET |
| E | VCVS |
| G | VCCS |
| H | CCVS |
| F | CCCS |
| X | サブ回路 |

---

## 11. CircuitStudio 現状機能一覧

### 11.1 実装済み機能

- コンポーネント配置 (14 デバイス: R, C, L, V, I, E, G, H, F, D, Q×2, M×2, GND)
- ワイヤー描画 (ドラッグ、ピンスナップ)
- ネットラベル配置
- 選択 (タップ: コンポーネント/ワイヤー/ラベル/ピン)
- 移動 (ドラッグ、ラバーバンディング対応)
- 回転 (`R` キー、90° 単位)
- 削除 (`Delete` キー)
- グリッドスナップ (10pt)
- ズーム (ピンチジェスチャー、0.1x–10x)
- パン (ドラッグ)
- ネット抽出 (Union-Find ベース、ジャンクション検出、ラベル割当)
- SPICE ネットリスト生成 (.model カード、制御電源、半導体対応)
- シミュレーション実行 (DC OP, AC, Transient, DC Sweep, Noise, TF, PZ)
- ERC (浮きピン、未接続、重複名、必須パラメータ、GND 存在)
- 波形表示 (LineMark、カーソル、トレース切替、ズーム)
- コンポーネントパレット (カテゴリ別、展開/折りたたみ)
- プロパティインスペクタ (位置、回転、パラメータ編集)

### 11.2 未実装機能 (業界標準との差分)

| 優先度 | 機能 | 業界での実装状況 |
|--------|------|----------------|
| **Critical** | Undo/Redo | 全ツールが実装 |
| **Critical** | コピー&ペースト | 全ツールが実装 |
| **High** | ミラー反転 | KiCad, LTspice, Altium が実装 |
| **High** | キーボードショートカット拡充 | 全ツールが豊富なショートカットを提供 |
| **High** | ジャンクション (T 接合の明示) | KiCad (必須), LTspice (自動), Altium |
| **Medium** | No-Connect フラグ | KiCad, Altium, OrCAD |
| **Medium** | 電源レールシンボル (VCC, VDD) | KiCad, Altium, OrCAD |
| **Medium** | クリック・ツー・プローブ | LTspice |
| **Medium** | 階層設計 | 全 PCB ツール + LTspice |
| **Low** | バスサポート | KiCad, Altium, OrCAD (PCB フロー向け) |
| **Low** | カスタムシンボルエディタ | 全ツール |
| **Low** | 波形数式演算 | LTspice, Qucs-S |

---

## 12. 参考資料

- [KiCad 8.0 Eeschema Documentation](https://docs.kicad.org/8.0/en/eeschema/eeschema.html)
- [KiCad 9.0 Eeschema Documentation](https://docs.kicad.org/9.0/en/eeschema/eeschema.html)
- [LTspice Schematic Editing Help](https://ltwiki.org/LTspiceHelp/LTspiceHelp/Schematic_Editing.htm)
- [LTspice Hot Keys Wiki](https://ltwiki.org/index.php?title=LTspice_Hot_Keys)
- [Analog Devices LTspice Keyboard Shortcuts](https://www.analog.com/en/resources/technical-articles/ltspice-keyboard-shortcuts.html)
- [Qucs-S Project](https://ra3xdh.github.io/)
- [Qucs-S Documentation](https://qucs-s-help.readthedocs.io/en/latest/)
- [Altium Designer Schematic Capture](https://www.altium.com/altium-designer/features/schematic-capture)
- [Altium Schematic Editor Shortcuts](https://www.altium.com/documentation/altium-designer/shortcut-keys/schematic-editors)
- [OrCAD Capture User Guide](https://i-t.com/wp-content/uploads/2019/05/cap_ug.pdf)
- [OrCAD X Capture](https://www.cadence.com/en_US/home/tools/pcb-design-and-analysis/orcad/orcad-capture.html)
