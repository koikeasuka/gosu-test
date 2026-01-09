require "gosu"
require_relative "distance_sensor"

# GPIO制御クラス（gpiogetコマンドを使用）
class GPIO
  def initialize(pin)
    @pin = pin
    @chip = "gpiochip0"

    # gpiogetが利用可能か確認
    unless system("which gpioget > /dev/null 2>&1")
      puts "警告: gpiogetコマンドが見つかりません。キーボード操作のみ有効です。"
      @available = false
    else
      @available = true
    end
  end

  def read
    return 1 unless @available  # gpiogetが使えない場合は常にHIGH（非接触状態）

    # gpioget でGPIO17の値を読み取り（バイアス設定でプルアップ）
    result = `gpioget -c #{@chip} -b pull-up #{@pin} 2>&1`.strip
    # 出力形式: "17"=inactive または "17"=active
    # =active = 1 (非接触状態), =inactive = 0 (接触した状態)
    result.include?("=active") ? 1 : 0
  end

  def cleanup
    # gpiogetは状態を変更しないのでクリーンアップ不要
  end
end

class Obstacle
  attr_accessor :x, :y, :width, :height, :type

  def initialize(x, y, width, height, type = :ground)
    @x = x
    @y = y
    @width = width
    @height = height
    @type = type  # :ground または :air
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
    color = @type == :air ? Gosu::Color::RED : Gosu::Color::GREEN
    Gosu.draw_rect(@x, @y, @width, @height, color)
  end
end

class Game < Gosu::Window
  GRAVITY = 1.5
  JUMP_POWER = -22
  OBSTACLE_SPEED = 10
  OBSTACLE_WIDTH = 20
  OBSTACLE_HEIGHT = 40
  SPAWN_INTERVAL = 80
  PLAYER_SCALE = 0.2  # プレイヤーの表示スケール

  # しゃがみ関連の定数
  SQUAT_DISTANCE_THRESHOLD = 201  # mm（201mm以上で立ち上がり）
  STAND_DISTANCE_THRESHOLD = 200  # mm（200mm以下でしゃがみ判定）

  # 空中障害物関連の定数
  AIR_OBSTACLE_HEIGHT = 30
  AIR_OBSTACLE_Y_OFFSET = 100  # 地面からの高さ
  AIR_OBSTACLE_SPAWN_RATE = 0.3  # 出現確率（30%）

  def initialize
    super 640, 480, true
    self.caption = "Jamping Game"

    # フレームレート制限（ラズパイのパフォーマンス向上）
    # 33.33ms = 30FPS（デフォルトは16.67ms = 60FPS）
    self.update_interval = 33.33

    # プレイヤー画像（通常/ジャンプ時、しゃがみ時）
    @player_stand = Gosu::Image.new("player.png")
    @player_squat = Gosu::Image.new("player_squat.png")

    @x = 100  # 画面左側に固定
    @y = 240
    @vy = 0
    @on_ground = true

    @obstacles = []
    @frame_count = 0
    @game_over = false

    # しゃがみ状態
    @is_squatting = false
    @distance_sensor = DistanceSensor.new
    @distance_check_counter = 0  # 距離センサーチェック用カウンター
    @cached_hitbox = nil  # 当たり判定キャッシュ

    # フォントを事前に作成してキャッシュ（パフォーマンス向上）
    @game_over_font = Gosu::Font.new(48)
    @restart_font = Gosu::Font.new(24)

    # ground_yを事前計算
    @ground_y = height - (@player_stand.height * PLAYER_SCALE)

    # GPIO17を入力として設定
    @jump_button = GPIO.new(17)
    @button_pressed = false
    @button_cooldown = 0
    @previous_button_state = false  # 前のフレームのボタン状態
  end

  def update
    # ボタンのクールダウン処理
    @button_cooldown -= 1 if @button_cooldown > 0

    # GPIO17の状態を確認（HIGHで非接触状態）
    gpio_value = @jump_button.read
    button_state = gpio_value == 1

    if @game_over
      # ゲームオーバー時：ボタンでリスタート
      if button_state && !@button_pressed
        reset_game
        @button_cooldown = 15  # リスタート後のクールダウン
      end
      @button_pressed = button_state
      return
    end

    # 距離センサーからしゃがみ判定
    update_squat_state

    # ジャンプ処理（接触から非接触に変わった瞬間、地面にいて、クールダウンが終わっている場合、しゃがんでいない場合）
    # エッジ検出: 前のフレームが接触状態(false)で、現在が非接触状態(true)
    if !@previous_button_state && button_state && @on_ground && @button_cooldown == 0 && !@is_squatting
      @vy = JUMP_POWER
      @on_ground = false
      @button_cooldown = 10  # 連続ジャンプ防止
    end

    # 次のフレームのために現在の状態を保存
    @previous_button_state = button_state

    # ジャンプ・落下処理
    @vy += GRAVITY
    @y += @vy

    # 地面判定（画面の下を地面にする）
    if @y >= @ground_y
      @y = @ground_y
      @vy = 0
      @on_ground = true
    end

    # 障害物の生成（地面または空中をランダムで生成）
    @frame_count += 1
    if @frame_count >= SPAWN_INTERVAL
      if rand < AIR_OBSTACLE_SPAWN_RATE
        # 空中障害物（30%の確率）
        obstacle_y = @ground_y - AIR_OBSTACLE_Y_OFFSET
        @obstacles << Obstacle.new(width, obstacle_y, OBSTACLE_WIDTH, AIR_OBSTACLE_HEIGHT, :air)
      else
        # 地面障害物（70%の確率）
        obstacle_y = height - OBSTACLE_HEIGHT
        @obstacles << Obstacle.new(width, obstacle_y, OBSTACLE_WIDTH, OBSTACLE_HEIGHT, :ground)
      end
      @frame_count = 0
    end

    # 障害物の更新
    @obstacles.each { |obstacle| obstacle.update(OBSTACLE_SPEED) }

    # 画面外の障害物を削除
    @obstacles.reject! { |obstacle| obstacle.off_screen? }

    # 衝突判定（しゃがみ対応）
    hitbox = player_hitbox
    @obstacles.each do |obstacle|
      if obstacle.colliding?(hitbox[:x], hitbox[:y], hitbox[:width], hitbox[:height])
        @game_over = true
        break
      end
    end
  end

  def draw
    # プレイヤーの描画（状態に応じて画像を切り替え）
    current_image = @is_squatting ? @player_squat : @player_stand
    current_image.draw(@x, @y, 0, PLAYER_SCALE, PLAYER_SCALE)

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
    @previous_button_state = false  # ボタン状態もリセット
    @is_squatting = false  # しゃがみ状態もリセット
    @cached_hitbox = nil  # キャッシュもリセット
  end

  def button_down(id)
    # キーボード入力も残す（デバッグ用）
    if id == Gosu::KB_B && @on_ground && !@game_over && !@is_squatting
      @vy = JUMP_POWER
      @on_ground = false
    end

    # Cキーでしゃがみテスト（デバッグ用）
    if id == Gosu::KB_C && @on_ground && !@game_over
      @is_squatting = !@is_squatting
      @cached_hitbox = nil
    end

    if id == Gosu::KB_RETURN && @game_over
      reset_game
    end

    close if id == Gosu::KB_ESCAPE
  end

  def update_squat_state
    return unless @distance_sensor

    # 3フレームごとに距離センサーをチェック（パフォーマンス向上）
    @distance_check_counter += 1
    return unless @distance_check_counter >= 3
    @distance_check_counter = 0

    distance = @distance_sensor.distance

    # デバッグ: 距離の値を表示
    puts "距離センサー: #{distance}mm, しゃがみ: #{@is_squatting}, 地面: #{@on_ground}" if distance

    return if distance.nil? || distance < 0
    return if distance > 2000 || distance < 30

    # ヒステリシスを使った状態判定
    if !@is_squatting && distance >= SQUAT_DISTANCE_THRESHOLD
      # しゃがむ（ジャンプ中でなければ）
      if @on_ground
        @is_squatting = true
        @cached_hitbox = nil  # キャッシュをクリア
        puts ">>> しゃがみ開始 <<<"
      end
    elsif @is_squatting && distance <= STAND_DISTANCE_THRESHOLD
      # 立つ
      @is_squatting = false
      @cached_hitbox = nil  # キャッシュをクリア
      puts ">>> しゃがみ解除 <<<"
    end
  end

  def player_hitbox
    # キャッシュがある場合は位置だけ更新して返す
    if @cached_hitbox
      @cached_hitbox[:x] = @x
      @cached_hitbox[:y] = @is_squatting ? @y + @cached_hitbox[:y_offset] : @y
      return @cached_hitbox
    end

    # キャッシュを計算
    if @is_squatting
      # しゃがみ時は高さを60%に縮小
      width = @player_squat.width * PLAYER_SCALE
      height = @player_squat.height * PLAYER_SCALE * 0.6
      y_offset = @player_squat.height * PLAYER_SCALE * 0.4
      @cached_hitbox = { x: @x, y: @y + y_offset, width: width, height: height, y_offset: y_offset }
    else
      # 通常時
      width = @player_stand.width * PLAYER_SCALE
      height = @player_stand.height * PLAYER_SCALE
      @cached_hitbox = { x: @x, y: @y, width: width, height: height, y_offset: 0 }
    end
    @cached_hitbox
  end

  def close
    @jump_button.cleanup if @jump_button
    super
  end
end

Game.new.show
