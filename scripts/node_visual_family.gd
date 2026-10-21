extends RefCounted
## Presentation identities only: never changes runtime types, ports or config.
const Design = preload("res://scripts/claude_design_theme.gd")

# Explicit aliases cover registry IDs, authored scene/script names and legacy
# server names. Source identity wins: maxpool/dropout share NeuronLayer's type.
const FAMILIES := {
	"input": &"data", "input_1d": &"data", "input_graph": &"data", "inputnode": &"data",
	"dataset": &"data", "datasetname": &"data", "label_group": &"data",
	"layer": &"layer", "neuronlayer": &"layer", "conv2d": &"layer", "gru_cell": &"layer", "grucell": &"layer",
	"neuron": &"operation", "layerconfig": &"operation", "activation_node": &"operation", "activationnode": &"operation",
	"maxpool": &"operation", "dropout": &"operation", "augment_tf": &"operation", "augment_tune": &"operation", "augmenttune": &"operation", "augmenttf": &"operation",
	"flatten": &"shape", "reshape": &"shape", "reshape2d": &"shape", "concat": &"shape", "layer_concat": &"shape",
	"softmax": &"output", "softmaxnode": &"output", "classifier": &"output", "classifier_graph": &"output", "classifiernode": &"output",
	"train_begin": &"training", "trainbegin": &"training", "train_input": &"training", "traininput": &"training",
	"train_rl": &"training", "trainrl": &"training", "run_model": &"training", "runmodel": &"training",
	"model_name": &"neutral", "modelname": &"neutral", "netname": &"neutral",
	"lua_env": &"neutral", "luaenv": &"neutral", "env_tag": &"neutral",
}


static func family(identities: Array, training: bool = false, input: bool = false) -> StringName:
	if training:
		return &"training"
	for identity in identities:
		var key := String(identity).get_file().get_basename().to_lower()
		if FAMILIES.has(key):
			return FAMILIES[key]
	return &"data" if input else &"neutral"


static func colors(role: StringName) -> Array[Color]:
	# Header, body, connector and ink are shared by live nodes and miniatures.
	match role:
		&"data": return [Design.INPUT_TOP, Design.INPUT_SOFT, Design.INPUT_WIRE, Design.INPUT_INK]
		&"layer": return [Design.LAYER_TOP, Design.LAYER_SOFT, Design.LAYER_WIRE, Design.LAYER_INK]
		&"operation": return [Design.ACTIVATION_TOP, Design.ACTIVATION_SOFT, Design.ACTIVATION_WIRE, Design.ACTIVATION_INK]
		&"shape": return [Design.SHAPE_TOP, Design.SHAPE_SOFT, Design.SHAPE_WIRE, Design.SHAPE_INK]
		&"output": return [Design.OUTPUT_TOP, Design.OUTPUT_SOFT, Design.OUTPUT_WIRE, Design.OUTPUT_INK]
		&"training": return [Design.TRAINING_TOP, Design.TRAINING_SOFT, Design.TRAINING_WIRE, Design.TRAINING_INK]
	return [Color("dcaef7"), Color("f3e4fd"), Design.LINE_STRONG, Design.INK_SECONDARY]
