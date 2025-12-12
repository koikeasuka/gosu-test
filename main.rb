require "gosu"

class Game < Gosu::Window
  SPEED = 5
  GRAVITY = 1
  JUMP_POWER = -20

  def initialize
    super 640, 480
    self.caption = "My Gosu Game"

    @player = Gosu::Image.new("player.png")
    @x = 320
    @y = 240
    @vy = 0
    @on_ground = true
  end

  def update
    @x -= SPEED if button_down?(Gosu::KB_LEFT)
    @x += SPEED if button_down?(Gosu::KB_RIGHT)

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
  end

  def draw
    @player.draw(@x, @y, 0)
  end

  def button_down(id)
    close if id == Gosu::KB_ESCAPE
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
