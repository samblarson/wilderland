# Store large float32 weights as float16 + Cast-to-float32 nodes (graph stays float32 at runtime).
import sys, onnx, numpy as np
from onnx import numpy_helper, helper, TensorProto
src, dst = sys.argv[1:3]
m = onnx.load(src); g = m.graph
new_nodes = []; n = 0
for init in list(g.initializer):
    if init.data_type == TensorProto.FLOAT and np.prod(init.dims) >= 4096:
        a = numpy_helper.to_array(init)
        if np.abs(a).max() > 6e4: continue
        name = init.name; h = numpy_helper.from_array(a.astype(np.float16), name + "__f16")
        g.initializer.remove(init); g.initializer.append(h)
        new_nodes.append(helper.make_node("Cast", [name + "__f16"], [name], to=TensorProto.FLOAT, name=name + "__cast")); n += 1
for i, nd in enumerate(new_nodes): g.node.insert(i, nd)
print("converted", n, "opset", [(o.domain, o.version) for o in m.opset_import])
onnx.save(m, dst)
