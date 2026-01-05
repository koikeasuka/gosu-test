# GPIO17を使ったジャンプゲーム実装プラン

## 概要
ラズパイのGPIO17をボタン入力として使用し、物理ボタンでジャンプ操作を可能にする。

## 必要なgem
```bash
gem install pi_piper
```

## 配線
- GPIO17（物理ピン11）→ ボタンの片側
- ボタンのもう片側 → GND（物理ピン6、9、14など）
- 内蔵プルアップ抵抗を使用（ボタンを押すとLOWになる）

## 実装コード

```ruby
require "gosu"
require "pi_piper"

class Obstacle
  attr_accessor :x, :y, :width, :height

  def initialize(x, y, width, height)
    @x = x
    @y = y
    @width = width
    @height = height
  end

  def update(speed)
    @x -= speed
  end

  def off_screen?
    @x + @width < 0
  end

  def colliding?(player_x, player_y, player_width, player_height)
    @x < player_x + player_width &&
      @x + @width > player_x &&
      @y < player_y + player_height &&
      @y + @height > player_y
  end

  def draw
    Gosu.draw_rect(@x, @y, @width, @height, Gosu::Color::GREEN)
  end
end

class Game < Gosu::Window
  GRAVITY = 1.5
  JUMP_POWER = -22
  OBSTACLE_SPEED = 10
  OBSTACLE_WIDTH = 20
  OBSTACLE_HEIGHT = 40
  SPAWN_INTERVAL = 80
  PLAYER_SCALE = 0.2

  def initialize
    super 640, 480
    self.caption = "Jamping Game"

    # フレームレート制限（ラズパイのパフォーマンス向上）
    self.update_interval = 33.33

    @player = Gosu::Image.new("player.png")
    @x = 100
    @y = 240
    @vy = 0
    @on_ground = true

    @obstacles = []
    @frame_count = 0
    @game_over = false

    # フォントを事前に作成してキャッシュ
    @game_over_font = Gosu::Font.new(48)
    @restart_font = Gosu::Font.new(24)

    # ground_yを事前計算
    @ground_y = height - (@player.height * PLAYER_SCALE)

    # GPIO17をプルアップ抵抗付きで入力として設定
    @jump_button = PiPiper::Pin.new(pin: 17, direction: :in, pull: :up)
    @button_pressed = false
    @button_cooldown = 0
  end

  def update
    # ボタンのクールダウン処理
    @button_cooldown -= 1 if @button_cooldown > 0

    # GPIO17の状態を確認（LOWで押された状態）
    button_state = @jump_button.read == 0

    if @game_over
      # ゲームオーバー時：ボタンでリスタート
      if button_state && !@button_pressed
        reset_game
        @button_cooldown = 15  # リスタート後のクールダウン
      end
      @button_pressed = button_state
      return
    end

    # ジャンプ処理（ボタンが押され、地面にいて、クールダウンが終わっている場合）
    if button_state && @on_ground && @button_cooldown == 0
      @vy = JUMP_POWER
      @on_ground = false
      @button_cooldown = 10  # 連続ジャンプ防止
    end

    # ジャンプ・落下処理
    @vy += GRAVITY
    @y += @vy

    # 地面判定
    if @y >= @ground_y
      @y = @ground_y
      @vy = 0
      @on_ground = true
    end

    # 障害物の生成
    @frame_count += 1
    if @frame_count >= SPAWN_INTERVAL
      obstacle_y = height - OBSTACLE_HEIGHT
      @obstacles << Obstacle.new(width, obstacle_y, OBSTACLE_WIDTH, OBSTACLE_HEIGHT)
      @frame_count = 0
    end

    # 障害物の更新
    @obstacles.each { |obstacle| obstacle.update(OBSTACLE_SPEED) }

    # 画面外の障害物を削除
    @obstacles.reject! { |obstacle| obstacle.off_screen? }

    # 衝突判定
    @obstacles.each do |obstacle|
      if obstacle.colliding?(@x, @y, @player.width * PLAYER_SCALE, @player.height * PLAYER_SCALE)
        @game_over = true
        break
      end
    end
  end

  def draw
    @player.draw(@x, @y, 0, PLAYER_SCALE, PLAYER_SCALE)
    @obstacles.each { |obstacle| obstacle.draw }

    if @game_over
      text = "GAME OVER"
      text_width = @game_over_font.text_width(text)
      @game_over_font.draw_text(text, (width - text_width) / 2, height / 2 - 50, 1, 1, 1, Gosu::Color::RED)

      restart_text = "Press button to Restart"
      restart_width = @restart_font.text_width(restart_text)
      @restart_font.draw_text(restart_text, (width - restart_width) / 2, height / 2 + 20, 1, 1, 1, Gosu::Color::WHITE)
    end
  end

  def reset_game
    @x = 100
    @y = 240
    @vy = 0
    @on_ground = true
    @obstacles = []
    @frame_count = 0
    @game_over = false
  end

  def button_down(id)
    # キーボード入力も残す（デバッグ用）
    if id == Gosu::KB_B && @on_ground && !@game_over
      @vy = JUMP_POWER
      @on_ground = false
    end

    if id == Gosu::KB_RETURN && @game_over
      reset_game
    end

    close if id == Gosu::KB_ESCAPE
  end
end

Game.new.show
```

## 実装のポイント

### 1. GPIO初期化
```ruby
@jump_button = PiPiper::Pin.new(pin: 17, direction: :in, pull: :up)
```
- `pin: 17`: GPIO17を使用
- `direction: :in`: 入力モード
- `pull: :up`: プルアップ抵抗を有効化（ボタンを押すとLOWになる）

### 2. ボタン状態の読み取り
```ruby
button_state = @jump_button.read == 0
```
- `read == 0`: LOWの時（ボタンが押されている時）にtrue

### 3. チャタリング防止
```ruby
@button_cooldown = 10
```
- クールダウンカウンタで連続入力を防止
- 1回のジャンプ後、10フレーム（約0.3秒）は次のジャンプができない

### 4. ゲームオーバー時のリスタート
```ruby
if button_state && !@button_pressed
  reset_game
  @button_cooldown = 15
end
```
- エッジ検出でボタンが押された瞬間を検知
- リスタート後もクールダウンで誤動作防止

## テスト方法

1. ラズパイ上で実行
```bash
ruby main.rb
```

2. GPIO17に接続したボタンを押してジャンプ
3. キーボードのBキーでもジャンプ可能（デバッグ用）
4. ESCキーで終了

## 注意事項

- ラズパイ上で実行する必要があります（GPIO使用のため）
- rootまたはgpioグループの権限が必要な場合があります
- pi_piperがインストールされていることを確認してください
