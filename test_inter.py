import traceback
import sys

try:
    import tensorflow as tf
    inter = tf.lite.Interpreter(model_path='assets/models/optp_v3_3.dat')
    inter.allocate_tensors()
    print("SUCCESS!")
    print("INPUTS:", inter.get_input_details())
    print("OUTPUTS:", inter.get_output_details())
except Exception as e:
    print("FAILED WITH EXCEPTION:")
    traceback.print_exc()
