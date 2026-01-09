# しゃがみ機能実装計画

## 概要

VL53L0X 距離センサーを使用して、プレイヤーがしゃがむ動作を実装する。
上から飛んでくる障害物を追加し、しゃがんで回避できるようにする。

## 目標

- 距離センサーの値でしゃがみ判定
- しゃがんだらキャラクターの高さが変わる
- 上から飛んでくる障害物を追加
- ジャンプ中はしゃがめない
- しゃがんでいる間はジャンプできない

## 現在の実装状況

### 既存ファイル

- `vl53.py` - VL53L0X センサーから距離（mm）を取得する Python スクリプト
- `distance_sensor.rb` - Python スクリプトを起動し、距離を読み取る Ruby クラス
- `main.rb` - メインゲームコード（GPIO17 でジャンプ、地面の障害物のみ）

### 現在の仕組み

1. **距離センサー:** VL53L0X ToF センサーが 20Hz で距離を測定
2. **ジャンプ:** GPIO17 の接触センサーでジャンプ
3. **障害物:** 地面を走ってくる障害物のみ（緑の矩形）

## 実装設計

### 1. しゃがみ判定の閾値設定

距離センサーの値に基づいてしゃがみ状態を判定します。

```ruby
# 定数の追加（main.rbのGameクラス内）
SQUAT_DISTANCE_THRESHOLD = 401  # mm（401mm以上で立ち上がり）
STAND_DISTANCE_THRESHOLD = 400  # mm（400mm以下でしゃがみ判定）
```

**ヒステリシス（ノイズ対策）:**

- しゃがむ: 距離が 401mm 以上になったとき
- 立つ: 距離が 400mm 以下になったとき

### 2. プレイヤーの状態管理

```ruby
# 新しいインスタンス変数
@is_squatting = false          # しゃがみ状態フラグ
@distance_sensor = nil         # 距離センサーインスタンス

# プレイヤー画像（2種類）
@player_stand = nil            # 通常/ジャンプ時の画像
@player_squat = nil            # しゃがみ時の画像
```

**画像の読み込み（initialize メソッド）:**

```ruby
def initialize
  # ...
  @player_stand = Gosu::Image.new("player.png")
  @player_squat = Gosu::Image.new("player_squat.png")
  # ...
end
```

### 3. 距離センサーの統合

現在、`GPIO`クラスが`DistanceSensor`をインスタンス化していますが、
これを`Game`クラスに移動します。

**修正前（GPIO クラス）:**

```ruby
class GPIO
  def initialize(pin)
    @distance_sensor = DistanceSensor.new  # ← これを削除
    # ...
  end
end
```

**修正後（Game クラス）:**

```ruby
class Game < Gosu::Window
  def initialize
    # ...
    @distance_sensor = DistanceSensor.new
    # ...
  end
end
```

### 4. しゃがみ処理の実装

#### update メソッドでの処理

```ruby
def update
  return if @game_over

  # 距離センサーからしゃがみ判定
  update_squat_state

  # ジャンプ処理（しゃがんでいない場合のみ）
  unless @is_squatting
    # 既存のジャンプ処理
  end

  # 重力・落下処理
  # 障害物処理
  # ...
end
```

#### しゃがみ状態更新メソッド（新規）

```ruby
def update_squat_state
  return unless @distance_sensor

  distance = @distance_sensor.distance
  return unless distance  # センサーエラー時はスキップ

  # ヒステリシスを使った状態判定
  if !@is_squatting && distance <= SQUAT_DISTANCE_THRESHOLD
    # しゃがむ（ジャンプ中でなければ）
    if @on_ground
      @is_squatting = true
      puts "しゃがみ開始（距離: #{distance}mm）"
    end
  elsif @is_squatting && distance >= STAND_DISTANCE_THRESHOLD
    # 立つ
    @is_squatting = false
    puts "しゃがみ解除（距離: #{distance}mm）"
  end
end
```

### 5. プレイヤー描画の変更

しゃがみ状態に応じて画像を切り替えます。

```ruby
def draw
  # プレイヤーの描画（状態に応じて画像を切り替え）
  current_image = @is_squatting ? @player_squat : @player_stand

  current_image.draw(@x, @y, 0, PLAYER_SCALE, PLAYER_SCALE)

  # 障害物の描画
  # ...
end
```

**描画のロジック:**

- 通常時: `player.png`を表示
- ジャンプ時: `player.png`を表示（通常時と同じ）
- しゃがみ時: `player_squat.png`を表示

**重要:** しゃがみ画像は通常画像と同じ高さで作成してください。
縦方向のスケールを変更せず、画像そのものがしゃがんだポーズになっている想定です。

### 6. 当たり判定の修正

しゃがみ状態に応じた当たり判定を実装します。

**手動で当たり判定サイズを調整**

しゃがみ時の当たり判定を画像より小さくしたい場合：

```ruby
def player_hitbox
  if @is_squatting
    # しゃがみ時は高さを60%に縮小（調整可能）
    width = @player_squat.width * PLAYER_SCALE
    height = @player_squat.height * PLAYER_SCALE * 0.6
    y_offset = @player_squat.height * PLAYER_SCALE * 0.4
    { x: @x, y: @y + y_offset, width: width, height: height }
  else
    # 通常時
    width = @player_stand.width * PLAYER_SCALE
    height = @player_stand.height * PLAYER_SCALE
    { x: @x, y: @y, width: width, height: height }
  end
end

# 衝突判定（updateメソッド内）
hitbox = player_hitbox
@obstacles.each do |obstacle|
  if obstacle.colliding?(hitbox[:x], hitbox[:y], hitbox[:width], hitbox[:height])
    @game_over = true
    break
  end
end
```

### 7. 上から来る障害物の追加

#### Obstacle クラスの拡張

```ruby
class Obstacle
  attr_accessor :x, :y, :width, :height, :type

  def initialize(x, y, width, height, type = :ground)
    @x = x
    @y = y
    @width = width
    @height = height
    @type = type  # :ground または :air
  end

  def draw
    color = @type == :air ? Gosu::Color::RED : Gosu::Color::GREEN
    Gosu.draw_rect(@x, @y, @width, @height, color)
  end
end
```

#### 障害物生成ロジックの修正

```ruby
# 定数の追加
AIR_OBSTACLE_HEIGHT = 30
AIR_OBSTACLE_Y_OFFSET = 100  # 地面から100ピクセル上

# 障害物の生成（updateメソッド内）
@frame_count += 1
if @frame_count >= SPAWN_INTERVAL
  # ランダムで地面または空中の障害物を生成
  if rand < 0.3  # 30%の確率で空中障害物
    obstacle_y = @ground_y - AIR_OBSTACLE_Y_OFFSET
    @obstacles << Obstacle.new(width, obstacle_y, OBSTACLE_WIDTH, AIR_OBSTACLE_HEIGHT, :air)
  else  # 70%の確率で地面障害物
    obstacle_y = height - OBSTACLE_HEIGHT
    @obstacles << Obstacle.new(width, obstacle_y, OBSTACLE_WIDTH, OBSTACLE_HEIGHT, :ground)
  end
  @frame_count = 0
end
```

### 8. 相互排他制御

ジャンプとしゃがみを相互に排他的にします。

#### ジャンプ処理の修正

```ruby
# ジャンプ処理（しゃがんでいない場合のみ）
if !@previous_button_state && button_state && @on_ground && @button_cooldown == 0 && !@is_squatting
  @vy = JUMP_POWER
  @on_ground = false
  @button_cooldown = 10
end
```

#### しゃがみ処理の修正（再掲）

```ruby
# しゃがむ処理（地面にいる場合のみ）
if !@is_squatting && distance <= SQUAT_DISTANCE_THRESHOLD
  if @on_ground  # ← ジャンプ中はしゃがめない
    @is_squatting = true
  end
end
```

## 実装手順

### Phase 1: 距離センサーの統合としゃがみ判定

1. `GPIO`クラスから`DistanceSensor`のインスタンス化を削除
2. `Game`クラスで`DistanceSensor`を初期化
3. `update_squat_state`メソッドを実装
4. しゃがみ状態のフラグ管理を追加
5. デバッグ出力でしゃがみ判定を確認

### Phase 2: プレイヤーのビジュアル変更

1. `player_squat.png`画像を読み込み
2. `draw`メソッドでしゃがみ時に画像を切り替え
3. `current_player_image`メソッドを実装
4. 当たり判定をしゃがみ対応に修正（画像のサイズで自動判定）

### Phase 3: 上から来る障害物の追加

1. `Obstacle`クラスに`type`属性を追加
2. 障害物生成ロジックを修正（地面/空中をランダム生成）
3. 障害物の描画色を種類別に変更（地面=緑、空中=赤）
4. 空中障害物の高さと位置を調整

### Phase 4: 相互排他制御

1. ジャンプ処理にしゃがみチェックを追加
2. しゃがみ処理にジャンプチェックを追加
3. 動作確認とテスト

### Phase 5: 調整とテスト

1. 距離センサーの閾値調整（実際の使用環境で）
2. しゃがみ高さ比率の調整
3. 障害物の出現確率と配置の調整
4. パフォーマンステスト（Raspberry Pi で 30FPS 維持）

## 定数一覧（追加・変更）

```ruby
# しゃがみ関連
SQUAT_DISTANCE_THRESHOLD = 300    # しゃがみ判定距離（mm）
STAND_DISTANCE_THRESHOLD = 400    # 立ち上がり判定距離（mm）
SQUAT_HEIGHT_RATIO = 0.5          # しゃがみ時の高さ比率

# 空中障害物関連
AIR_OBSTACLE_HEIGHT = 30          # 空中障害物の高さ
AIR_OBSTACLE_Y_OFFSET = 100       # 地面からの高さ
AIR_OBSTACLE_SPAWN_RATE = 0.3     # 出現確率（30%）
```

## ファイル構成（実装後）

```
gosu-test/
├── main.rb                    # メインゲーム（しゃがみ機能追加）
├── distance_sensor.rb         # 距離センサークラス（変更なし）
├── vl53.py                    # VL53L0Xセンサー読み取り（変更なし）
├── player.png                 # プレイヤー画像（通常/ジャンプ時）
├── player_squat.png           # プレイヤー画像（しゃがみ時）
├── PLAN_squat.md             # このファイル
└── README.md                  # セットアップガイド（更新予定）
```

## 画像ファイルの要件

### player.png（通常/ジャンプ時）

- 既存の画像をそのまま使用
- 立っている、またはジャンプしているポーズ

### player_squat.png（しゃがみ時）

- **サイズ:** player.png と同じサイズ推奨
- **ポーズ:** しゃがんだ状態
- **当たり判定:**
  - コードで当たり判定を調整（実装が複雑）
- **配置:** 画像の下端が地面に接地するように作成

## 技術的考慮事項

### 距離センサーの閾値

閾値は使用環境に合わせて調整が必要です。

**推奨キャリブレーション手順:**

1. 立った状態での距離を計測（例: 600mm）
2. しゃがんだ状態での距離を計測（例: 200mm）
3. 中間値を閾値に設定
4. ヒステリシス幅を設定（100mm 程度）

### パフォーマンス

- 距離センサーは 20Hz で更新（50ms 間隔）
- ゲームループは 30FPS（33.33ms 間隔）
- センサー読み取りは非同期なので、ゲームループをブロックしない

### エラーハンドリング

```ruby
def update_squat_state
  return unless @distance_sensor

  distance = @distance_sensor.distance

  # センサーエラー（-1）または nil の場合
  return if distance.nil? || distance < 0

  # 異常値チェック（VL53L0Xの測定範囲: 30mm〜2000mm）
  return if distance > 2000 || distance < 30

  # しゃがみ判定処理
  # ...
end
```

### デバッグモード

開発時のデバッグ用機能：

```ruby
# キーボードでしゃがみテスト
def button_down(id)
  # ...

  # Cキーでしゃがみ（デバッグ用）
  if id == Gosu::KB_C && @on_ground && !@game_over
    @is_squatting = !@is_squatting
    puts "しゃがみ切り替え: #{@is_squatting}"
  end
end
```

## トラブルシューティング

### しゃがみが反応しない

1. **距離センサーの動作確認:**

   ```bash
   python ~/vl53env/bin/python vl53.py
   ```

   距離が表示されるか確認

2. **閾値の調整:** 実際の距離に合わせて閾値を変更

3. **デバッグ出力:** 距離の値をコンソールに表示
   ```ruby
   puts "距離: #{distance}mm, しゃがみ: #{@is_squatting}"
   ```

### ジャンプとしゃがみが同時に発生

- 相互排他チェックが正しく実装されているか確認
- `@on_ground`フラグの状態を確認

### 当たり判定がおかしい

- `player_height`と`player_y_adjusted`の計算を確認
- しゃがみ時のオフセット計算を見直し

### 空中障害物が地面の障害物と被る

- 出現間隔とランダム生成のロジックを調整
- 連続で同じタイプが出ないようにする制御を追加

## 今後の拡張案

1. **スコアシステム:**

   - 障害物を回避するごとにスコア加算
   - ハイスコアの記録

2. **難易度調整:**

   - 時間経過で障害物の速度を上げる
   - 障害物の出現間隔を短くする

3. **ビジュアル改善:**

   - ~~しゃがみ用の別画像を用意~~ ✅ 実装済み（player_squat.png）
   - 空中障害物に鳥の画像を使用
   - アニメーション効果（走るモーション、ジャンプモーション）

4. **音声フィードバック:**

   - しゃがみ時に効果音
   - 障害物衝突時に音

5. **複数パターンの障害物:**
   - 高さの異なる空中障害物
   - 連続で複数の障害物が来るパターン

## 参考資料

- VL53L0X センサー: https://www.adafruit.com/product/3317
- Gosu ドキュメント: https://www.libgosu.org/rdoc/
- Raspberry Pi GPIO: https://pinout.xyz/

---

**作成日:** 2026-01-09
**実装目標:** しゃがみ機能と上から来る障害物の追加
