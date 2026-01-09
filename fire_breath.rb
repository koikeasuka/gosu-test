require 'gosu'

class FireBreath
  DURATION = 20  # フレーム数（約0.66秒 @ 30FPS）
  PARTICLE_COUNT = 15  # パーティクル数

  attr_reader :active

  def initialize(window, player_x, player_y, player_scale = 0.2)
    @window = window
    @x = player_x + (100 * player_scale)  # プレイヤーの右側
    @y = player_y + (50 * player_scale)   # プレイヤーの中心付近
    @frame = 0
    @active = true
    @use_image = false

    # 炎の画像を読み込み（存在する場合）
    begin
      if File.exist?('fire.png')
        @image = Gosu::Image.new('fire.png')
        @use_image = true
      end
    rescue => e
      puts "[FireBreath] 画像読み込みエラー: #{e.message}"
    end

    # パーティクルシステムの初期化
    @particles = []
    PARTICLE_COUNT.times do |i|
      @particles << {
        x: @x + rand(-10..10),
        y: @y + rand(-10..10),
        vx: rand(3..8),        # 右方向の速度
        vy: rand(-2..2),       # 上下のランダムな速度
        size: rand(8..16),     # パーティクルのサイズ
        hue: rand(0..30)       # 色相（赤〜オレンジ）
      }
    end
  end

  def update
    @frame += 1
    @active = false if @frame >= DURATION

    # パーティクルの更新
    @particles.each do |p|
      p[:x] += p[:vx]
      p[:y] += p[:vy]
      p[:size] *= 0.95  # 徐々に小さくなる
    end
  end

  def draw
    return unless @active

    # 透明度を時間経過で変化（フェードアウト）
    alpha = [(255 - (@frame * 12)).to_i, 0].max

    if @use_image && @image
      # 画像ベースの描画
      color = Gosu::Color.new(alpha, 255, 255, 255)
      @image.draw(@x, @y, 1, 1.0, 1.0, color)
    else
      # パーティクルベースの描画
      @particles.each do |p|
        next if p[:size] < 1

        # 色の計算（赤〜オレンジ〜黄色）
        brightness = (255 * (@frame / DURATION.to_f)).to_i
        color = case p[:hue]
                when 0..10
                  Gosu::Color.new(alpha, 255, 100 + brightness, 0)  # 赤〜オレンジ
                when 11..20
                  Gosu::Color.new(alpha, 255, 150 + brightness, 0)  # オレンジ
                else
                  Gosu::Color.new(alpha, 255, 200 + brightness, 50) # 黄色
                end

        # 円を描画（四角形で近似）
        draw_circle(p[:x], p[:y], p[:size], color)
      end
    end
  end

  def finished?
    !@active
  end

  private

  def draw_circle(x, y, radius, color)
    # 円を多角形で近似して描画
    segments = 8
    (0...segments).each do |i|
      angle1 = (2 * Math::PI * i) / segments
      angle2 = (2 * Math::PI * (i + 1)) / segments

      x1 = x + radius * Math.cos(angle1)
      y1 = y + radius * Math.sin(angle1)
      x2 = x + radius * Math.cos(angle2)
      y2 = y + radius * Math.sin(angle2)

      @window.draw_triangle(
        x, y, color,
        x1, y1, color,
        x2, y2, color,
        2  # Z-order
      )
    end
  end
end
