require "gosu"

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
  GRAVITY = 1
  JUMP_POWER = -20
  OBSTACLE_SPEED = 5
  OBSTACLE_WIDTH = 20
  OBSTACLE_HEIGHT = 40
  SPAWN_INTERVAL = 100
  PLAYER_SCALE = 0.2  # プレイヤーの表示スケール

  def initialize
    super 640, 480
    self.caption = "Jamping Game"

    # フレームレート制限（ラズパイのパフォーマンス向上）
    # 33.33ms = 30FPS（デフォルトは16.67ms = 60FPS）
    self.update_interval = 33.33

    @player = Gosu::Image.new("player.png")
    @x = 100  # 画面左側に固定
    @y = 240
    @vy = 0
    @on_ground = true

    @obstacles = []
    @frame_count = 0
    @game_over = false

    # フォントを事前に作成してキャッシュ（パフォーマンス向上）
    @game_over_font = Gosu::Font.new(48)
    @restart_font = Gosu::Font.new(24)

    # ground_yを事前計算
    @ground_y = height - (@player.height * PLAYER_SCALE)
  end

  def update
    return if @game_over

    # ジャンプ・落下処理
    @vy += GRAVITY
    @y += @vy

    # 地面判定（画面の下を地面にする）
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
