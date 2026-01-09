require_relative 'voice_input'

puts "音声入力のテスト開始..."
puts "5秒間マイクに向かって声を出してください"
puts ""

voice = VoiceInput.new

if voice.instance_variable_get(:@thread)
  5.times do |i|
    sleep(1)
    if voice.voice_detected?
      puts "✅ #{i+1}秒目: 音声検出成功！"
      voice.reset
    else
      puts "⏳ #{i+1}秒目: 待機中..."
    end
  end

  voice.stop
  puts ""
  puts "テスト終了"
else
  puts "❌ 音声入力が初期化されませんでした"
  puts "マイクの接続を確認してください"
end
