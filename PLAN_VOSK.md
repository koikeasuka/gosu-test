# Vosk 音声入力による炎を吹く演出の実装計画

## 概要

Vosk を使った音声認識により、音声入力（発声）を検出してキャラクターが炎を吹く演出を追加する。

## 目標

- 音声入力（任意の発声）を検出
- 音声を検出したら、キャラクターが炎を吹くアニメーション/エフェクトを表示
- 既存の GPIO ジャンプ機能と共存

## 技術スタック

### 必要な Gem

```ruby
gem 'vosk'          # Vosk音声認識ライブラリ
gem 'portaudio'     # 音声入力キャプチャ
```

### Vosk モデル

- 小型モデル: `vosk-model-small-ja-0.22` (日本語)
- または `vosk-model-small-en-us-0.15` (英語)
- モデルサイズ: 約 50MB
- ダウンロード元: https://alphacephei.com/vosk/models

## アーキテクチャ設計

### 1. VoiceInput クラス

```ruby
class VoiceInput
  def initialize
    # Voskモデルのロード
    # マイク入力ストリームの初期化
    # 音声認識スレッドの起動
  end

  def voice_detected?
    # 音声入力があったかを返す（ブール値）
    # スレッドセーフなフラグで管理
  end

  def reset
    # 音声検出フラグをリセット
  end

  def stop
    # スレッドとストリームを停止
  end
end
```

### 2. FireBreath クラス (新規)

炎を吹く演出を管理するクラス。

```ruby
class FireBreath
  attr_reader :active

  def initialize(window, player_x, player_y)
    # 炎の画像/パーティクルの初期化
    # 位置、サイズ、持続時間の設定
  end

  def update
    # アニメーションフレームの更新
    # 持続時間カウント
    # 終了判定
  end

  def draw
    # 炎エフェクトの描画
  end

  def finished?
    # 演出が終了したか
  end
end
```

## 実装詳細

### Phase 1: Vosk 音声認識の統合

#### 1.1 依存関係のインストール

```bash
# システムレベルの依存
sudo apt-get install portaudio19-dev  # Raspberry Pi
brew install portaudio                 # macOS

# Rubyのgem
gem install vosk
gem install portaudio
```

#### 1.2 Vosk モデルのダウンロード

```bash
cd /path/to/gosu-test
wget https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip
unzip vosk-model-small-ja-0.22.zip
mv vosk-model-small-ja-0.22 vosk-model
```

#### 1.3 VoiceInput クラスの実装

- 別スレッドでマイク入力を常時監視
- 音声を検出したらフラグを立てる（発話の開始/終了を検出）
- スレッドセーフなキュー or Mutex で状態管理
- Vosk の部分認識結果 (partial result) を利用して低遅延化

**音声検出のロジック:**

```ruby
# 認識結果の例
# partial: {"partial": "こんに"}
# final: {"text": "こんにちは"}

# 任意の発声を検出 = partial結果が空文字でなくなったタイミング
```

### Phase 2: 炎を吹く演出の実装

#### 2.1 炎のビジュアル設計

**オプション 1: 画像ベース**

- `fire.png`などの炎画像を用意
- プレイヤーの前方に表示
- フェードイン/フェードアウトで演出

**オプション 2: パーティクルシステム**

- 複数の小さな炎パーティクルを生成
- ランダムな動きで炎らしさを演出
- Gosu の描画機能で赤/オレンジの円を多数描画

**推奨: オプション 1（シンプル実装）**

#### 2.2 FireBreath クラスの実装

```ruby
class FireBreath
  DURATION = 20  # フレーム数（約0.66秒 @ 30FPS）

  def initialize(window, player_x, player_y)
    @image = Gosu::Image.new('fire.png')
    @x = player_x + 50  # プレイヤーの右側
    @y = player_y
    @frame = 0
    @active = true
  end

  def update
    @frame += 1
    @active = false if @frame >= DURATION
  end

  def draw
    # 透明度を時間経過で変化
    alpha = [255 - (@frame * 12), 0].max
    color = Gosu::Color.new(alpha, 255, 255, 255)
    @image.draw(@x, @y, 1, 1.0, 1.0, color)
  end

  def finished?
    !@active
  end
end
```

### Phase 3: Game クラスへの統合

#### 3.1 初期化処理の追加

```ruby
def initialize
  # ... 既存コード ...

  @voice_input = VoiceInput.new
  @fire_breaths = []  # 炎エフェクトの配列
end
```

#### 3.2 update メソッドの修正

```ruby
def update
  return if @game_over

  # 既存のGPIO処理...

  # 音声入力の検出
  if @voice_input.voice_detected?
    # 炎を吹く演出を開始
    @fire_breaths << FireBreath.new(self, @x, @y)
    @voice_input.reset
  end

  # 炎エフェクトの更新
  @fire_breaths.each(&:update)
  @fire_breaths.delete_if(&:finished?)

  # ... 既存の障害物処理など ...
end
```

#### 3.3 draw メソッドの修正

```ruby
def draw
  @image.draw(@x, @y, 0, PLAYER_SCALE, PLAYER_SCALE)

  # 炎エフェクトの描画
  @fire_breaths.each(&:draw)

  # ... 既存の障害物描画など ...
end
```

#### 3.4 終了処理の追加

```ruby
def close
  @voice_input.stop
  super
end
```

## 実装手順

### Step 1: 環境準備

1. PortAudio のインストール
2. 必要な gem のインストール
3. Vosk モデルのダウンロードと配置

### Step 2: VoiceInput クラス実装

1. `voice_input.rb`ファイルを作成
2. Vosk の初期化処理
3. マイク入力の取得
4. 音声検出ロジック（スレッド処理）
5. 動作確認（音声検出のログ出力）

### Step 3: FireBreath クラス実装

1. `fire_breath.rb`ファイルを作成
2. 炎画像の準備 or パーティクル描画実装
3. アニメーション処理
4. 単体テスト（キーボード入力で炎を出すテスト）

### Step 4: 統合

1. `main.rb`への統合
2. VoiceInput と FireBreath のインスタンス生成
3. ゲームループへの組み込み
4. 動作確認

### Step 5: 調整・最適化

1. 炎の表示位置調整
2. 持続時間の調整
3. 音声検出感度の調整
4. パフォーマンステスト

## ファイル構成（実装後）

```
gosu-test/
├── main.rb              # メインゲームコード（統合処理追加）
├── voice_input.rb       # 音声入力クラス（新規）
├── fire_breath.rb       # 炎演出クラス（新規）
├── player.png           # 既存プレイヤー画像
├── fire.png             # 炎画像（新規）
├── vosk-model/          # Voskモデルディレクトリ（新規）
│   └── ... (モデルファイル)
├── Gemfile              # 依存gem管理（新規 or 更新）
└── PLAN_VOSK.md         # このファイル
```

## 技術的考慮事項

### スレッド処理

- Gosu のゲームループはメインスレッド
- Vosk の音声認識は別スレッドで実行
- `Mutex`または`Queue`でスレッド間通信
- Ruby 3.x の Ractor 利用も検討可能

### パフォーマンス

- Vosk の認識処理は CPU 負荷が高い
- 小型モデルを使用して負荷軽減
- Raspberry Pi での動作確認が必要
- 必要に応じて FPS 制限を調整

### 音声検出感度

- 環境音でも反応する可能性あり
- Vosk の`partial_result`の長さで閾値設定
- 例: 2 文字以上認識されたら発声と判定

### エラーハンドリング

- マイクが接続されていない場合
- Vosk モデルが見つからない場合
- 音声認識の初期化失敗
- → フォールバック: 音声入力を無効化してゲーム続行

## テスト計画

### 単体テスト

1. VoiceInput: 音声検出フラグの動作確認
2. FireBreath: 描画とアニメーション確認

### 統合テスト

1. 発声 → 炎演出のトリガー確認
2. 連続発声時の挙動
3. GPIO + 音声の同時動作

### パフォーマンステスト

1. FPS 維持確認（目標: 30FPS 安定）
2. Raspberry Pi 実機での動作確認

## 参考資料

- Vosk 公式: https://alphacephei.com/vosk/
- Vosk Models: https://alphacephei.com/vosk/models
- Gosu Documentation: https://www.libgosu.org/rdoc/
- PortAudio: http://www.portaudio.com/

## 実装見積もり

- Phase 1 (Vosk 統合): VoiceInput クラス実装
- Phase 2 (炎演出): FireBreath クラス実装
- Phase 3 (統合): main.rb への組み込みと調整

---

**最終目標:** 音声入力でキャラクターが炎を吹く、直感的で楽しいゲーム体験の実装
