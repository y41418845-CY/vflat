import coremltools as ct
import tensorflow as tf
import os
import sys

print("TensorFlow Version:", tf.__version__)
print("CoreMLTools Version:", ct.__version__)

model_path = "assets/models/optp_v3_3.dat"
output_path = "ios/Sources/Core/Dewarp/OPTPModel.mlpackage"

print(f"Loading TFLite model from {model_path}...")
try:
    # 嘗試用 tf.lite 載入模型檢查輸入輸出
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    print("=== TFLite Model Input Details ===")
    for inp in input_details:
        print(f"  Name: {inp['name']}, Shape: {inp['shape']}, Dtype: {inp['dtype']}")
        
    print("=== TFLite Model Output Details ===")
    for out in output_details:
        print(f"  Name: {out['name']}, Shape: {out['shape']}, Dtype: {out['dtype']}")

    # 執行 CoreML 轉換
    print("\nConverting to CoreML...")
    mlmodel = ct.convert(
        model_path,
        source="tensorflow"
    )
    print("Conversion success! Model spec:")
    print(mlmodel)
    
    mlmodel.save(output_path)
    print(f"Saved CoreML model package to: {output_path}")

except Exception as e:
    print(f"Error during model conversion: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
