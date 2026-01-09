import time
import board
import busio
import adafruit_vl53l0x

def main():
    # I2C 初期化
    i2c = busio.I2C(board.SCL, board.SDA)

    # センサー初期化
    sensor = adafruit_vl53l0x.VL53L0X(i2c)

    # 任意：測定精度設定（デフォルトでOKなら不要）
    # sensor.measurement_timing_budget = 20000  # us

    while True:
        try:
            distance_mm = sensor.range  # 距離（mm）
            print(distance_mm, flush=True)
            time.sleep(0.05)  # 20Hz
        except Exception as e:
            # 一時的なI2Cエラー対策
            print(-1, flush=True)
            time.sleep(0.1)

if __name__ == "__main__":
    main()
