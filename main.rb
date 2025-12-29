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

  def initialize
    super 640, 480
    self.caption = "T-Rex Game"

    @player = Gosu::Image.new("player.png")
    @x = 100  # 画面左側に固定
    @y = 240
    @vy = 0
    @on_ground = true

    @obstacles = []
    @frame_count = 0
    @game_over = false
  end

  def update
    # ジャンプ・落下処理
    @vy += GRAVITY
    @y += @vy

    # 地面判定（画面の下を地面にする）
    ground_y = height - @player.height
    if @y >= ground_y
      @y = ground_y
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
  end

  def draw
    @player.draw(@x, @y, 0)
    @obstacles.each { |obstacle| obstacle.draw }
  end

  def button_down(id)
    if id == Gosu::KB_SPACE && @on_ground
      @vy = JUMP_POWER
      @on_ground = false
    end

    close if id == Gosu::KB_ESCAPE
  end
end

Game.new.show
