class DistanceSensor
  def initialize
    python = File.expand_path("~/vl53env/bin/python")
    script = File.expand_path("./vl53.py")

    @io = IO.popen("#{python} #{script}", "r")
    @latest_distance = nil
  end

  # 距離をそのまま返す（mm）
  def distance
    if (line = @io.gets)
      @latest_distance = line.to_i
    end
    @latest_distance
  rescue
    @latest_distance
  end
end
