require 'thread'

class VoiceInput
  # 音量レベルの閾値（この値を超えたら音声を検出）
  VOLUME_THRESHOLD = 0.05  # 0.0〜1.0の範囲（調整可能）

  # サンプリング間隔（秒）
  SAMPLE_INTERVAL = 0.3

  def initialize
    @mutex = Mutex.new
    @detected = false
    @running = false
    @thread = nil

    # soxがインストールされているか確認
    unless system("which sox > /dev/null 2>&1")
      puts "[VoiceInput] 警告: soxコマンドが見つかりません"
      puts "[VoiceInput] 音声入力機能は無効になります（Fキーでテスト可能）"
      puts "[VoiceInput] インストール: brew install sox"
      return
    end

    # マイクデバイスの確認
    unless check_microphone
      puts "[VoiceInput] 警告: マイクが見つかりません"
      puts "[VoiceInput] 音声入力機能は無効になります（Fキーでテスト可能）"
      return
    end

    # 音声認識スレッドを起動
    start_listening
    puts "[VoiceInput] 音声入力を開始しました（音量閾値: #{VOLUME_THRESHOLD}）"
    puts "[VoiceInput] マイクに向かって声を出すと炎を吹きます"
  rescue => e
    puts "[VoiceInput] エラー: 音声入力の初期化に失敗しました (#{e.message})"
    puts "[VoiceInput] 音声入力機能は無効になります（Fキーでテスト可能）"
  end

  def voice_detected?
    @mutex.synchronize { @detected }
  end

  def reset
    @mutex.synchronize { @detected = false }
  end

  def stop
    @running = false
    @thread&.join(1.0)  # 最大1秒待つ
    puts "[VoiceInput] 音声入力を停止しました"
  end

  private

  def check_microphone
    # ALSA録音デバイスが存在するか確認
    # arecordコマンドで録音デバイスリストを取得
    output = `arecord -l 2>&1`

    # 録音デバイスが1つ以上存在するか確認
    if output.include?("card") || output.include?("カード")
      puts "[VoiceInput] マイクデバイスを検出しました"
      return true
    else
      puts "[VoiceInput] デバッグ: arecord -l の出力:"
      puts output
      return false
    end
  rescue => e
    puts "[VoiceInput] マイク確認エラー: #{e.message}"
    return false
  end

  def start_listening
    @running = true
    @thread = Thread.new do
      begin
        listen_loop
      rescue => e
        puts "[VoiceInput] エラー: #{e.message}"
        puts e.backtrace.first(3)
        @running = false
      end
    end
  end

  def listen_loop
    sample_count = 0
    while @running
      begin
        # soxのrecコマンドで短時間録音して音量レベルを取得
        # -n: 出力ファイルなし（nullデバイス）
        # trim 0 0.3: 0.3秒録音
        # stat: 統計情報を出力（標準エラーに出力されるので2>&1でリダイレクト）

        output = `rec -n trim 0 #{SAMPLE_INTERVAL} stat 2>&1`
        sample_count += 1

        # 最初の2回は詳細なデバッグ出力
        if sample_count <= 2
          puts "[VoiceInput] デバッグ #{sample_count}: recコマンド出力:"
          puts output
          puts "---"
        end

        # 統計情報から最大振幅（Maximum amplitude）を抽出
        # 出力例: "Maximum amplitude:     0.123456"
        if output =~ /Maximum amplitude:\s+([\d.]+)/
          max_amplitude = $1.to_f

          # 音量を常に表示（最初の10回）
          if sample_count <= 10
            puts "[VoiceInput] サンプル#{sample_count}: 音量 #{(max_amplitude * 100).round(1)}% (閾値: #{(VOLUME_THRESHOLD * 100).round(1)}%)"
          end

          # 閾値を超えたら音声検出
          if max_amplitude > VOLUME_THRESHOLD
            @mutex.synchronize { @detected = true }
            puts "[VoiceInput] 🔥 音声検出！（音量: #{(max_amplitude * 100).round(1)}%）"
            sleep(0.5)  # 連続検出を防ぐための短い待機
          end
        else
          # Maximum amplitudeが見つからない場合
          if sample_count <= 2
            puts "[VoiceInput] 警告: Maximum amplitudeが見つかりません"
          end
        end

      rescue => e
        puts "[VoiceInput] サンプリングエラー: #{e.message}"
        puts e.backtrace.first(3)
        sleep(1.0)
      end
    end
  end
end
